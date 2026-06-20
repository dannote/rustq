defmodule RustQ.Meta do
  @moduledoc """
  Valid-Elixir macro frontend for generating RustQ Rust fragments.

  `defrust` captures a normal Elixir function-shaped body plus its preceding
  `@spec`, lowers that quoted Elixir AST to Rust, and exposes generated Rust
  items through `__rustq_items__/0` and `__rustq_source__/0`.

  `defrustmod` is for RustQ-owned Rust module structure. Prefer its block form
  when RustQ is generating the Rust module and the nested functions. Do not use
  it as a hand-written alias for Rust modules/types that are owned by another
  generator or crate; those callers should derive/render their Rust paths at
  their own codegen boundary instead of pretending external Rust modules are
  Elixir modules.

  Prefer `@spec` plus `defrust` for user-facing Rusty Elixir. Generated or
  external Rust paths should normally be expressed as ordinary remote types such
  as `GeneratedOpts.OvalOpts.t(R.lifetime(:a))`; use `RustQ.Type` markers such
  as `R.ref/1`, `R.nif_result/1`, `R.unit/0`, `R.slice/1`, and `R.lifetime/1`
  only where Elixir typespecs need Rust-specific precision. `RustQ.Meta.Ast.quoted/2`
  is a low-level bridge for internal generators that already hold RustQ AST
  signature metadata; it is not the intended authoring surface.

  Preferred Rusty-Elixir body forms are ordinary Elixir where possible:

    * final `:ok` under `NifResult<()>` returns `Ok(())`
    * `name = expression` lowers to Rust `let name = expression`
    * method calls, field access, aliases, and Elixir tuples lower to their Rust
      equivalents
    * plural alias calls such as `Atoms.fill()` lower to snake-case Rust module
      calls such as `atoms::fill()`
    * ordinary Elixir macros are expanded before lowering, so reusable body
      fragments can use `defmacro`, `quote`, and `unquote`
    * `unwrap!(expression)` is the explicit spelling for Rust `expression?`
    * `ref(expression)` / `mut_ref(expression)` spell Rust borrows; `deref(expression)` spells Rust dereference
    * Option branching should use Elixir `case`, for example
      `case maybe do {:some, value} -> ...; :none -> ... end`; do not introduce
      Rust-shaped `if_let` syntax at the authoring layer

  Escape hatches such as `raw_expr!` remain low-level last resorts, not the
  normal way to reference project-owned Rust modules or types.
  """

  alias RustQ.Meta.Ast
  alias RustQ.Meta.Type
  alias RustQ.Meta.Validate
  alias RustQ.Rust
  alias RustQ.Rust.AST.Render

  defmacro __using__(_opts) do
    quote do
      import RustQ.Meta
      Module.register_attribute(__MODULE__, :rustq_defs, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_mod_aliases, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_current_rust_mod, accumulate: false)
      Module.register_attribute(__MODULE__, :nif, accumulate: false)
      Module.register_attribute(__MODULE__, :allow, accumulate: true)
      @before_compile RustQ.Meta
    end
  end

  defmacro defrustmod(alias_ast, opts \\ []) do
    mapping = rust_module_mapping!(alias_ast, opts)

    quote do
      @rustq_mod_aliases unquote(Macro.escape(mapping))
    end
  end

  defmacro defrustmod(alias_ast, opts, do: block) do
    {alias_parts, rust_parts} = rust_module_mapping!(alias_ast, opts)

    quote do
      @rustq_mod_aliases unquote(Macro.escape({alias_parts, rust_parts}))
      Module.put_attribute(__MODULE__, :rustq_current_rust_mod, unquote(Macro.escape(rust_parts)))
      unquote(block)
      Module.delete_attribute(__MODULE__, :rustq_current_rust_mod)
    end
  end

  defmacro defrust(call_ast, do: body_ast) do
    {name, _meta, args} = call_ast
    arity = length(args || [])

    stub_args =
      if arity == 0, do: [], else: for(index <- 1..arity//1, do: Macro.var(:"_arg#{index}", nil))

    quote do
      @rustq_defs {unquote(Macro.escape(call_ast)), unquote(Macro.escape(body_ast)),
                   RustQ.Meta.Attrs.take_pending(__MODULE__),
                   RustQ.Meta.Attrs.current_rust_mod(__MODULE__)}
      def unquote(name)(unquote_splicing(stub_args)), do: :erlang.nif_error(:rustq_defrust_stub)
    end
  end

  defmacro __before_compile__(env) do
    defs = Module.get_attribute(env.module, :rustq_defs) |> List.wrap() |> Enum.reverse()
    specs = Module.get_attribute(env.module, :spec) |> List.wrap()
    type_aliases = env.module |> Module.get_attribute(:type) |> Type.type_aliases()
    rust_modules = env.module |> Module.get_attribute(:rustq_mod_aliases) |> rust_module_map()

    built_asts = Enum.map(defs, &Ast.build_ast(&1, specs, type_aliases, rust_modules, env))
    asts = Enum.map(built_asts, & &1.ast)
    type_asts = Ast.build_type_asts(type_aliases)
    type_items = Enum.map(type_asts, &Validate.item_ast/1)
    rust_items = Ast.group_module_asts(built_asts)
    rendered_items = Enum.map(rust_items, &Validate.item_ast/1)
    items = type_items ++ rendered_items

    type_source = Enum.map_join(type_items, "\n\n", &Rust.to_fragment/1)

    function_source =
      Enum.map_join(rust_items, "\n\n", &Render.render_item/1)

    source = [type_source, function_source] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")

    quote do
      @doc false
      def __rustq_asts__, do: unquote(Macro.escape(asts))

      @doc false
      def __rustq_types__, do: unquote(Macro.escape(type_aliases))

      @doc false
      def __rustq_type_asts__, do: unquote(Macro.escape(type_asts))

      @doc false
      def __rustq_type_items__, do: unquote(Macro.escape(type_items))

      @doc false
      def __rustq_items__, do: unquote(Macro.escape(items))

      @doc false
      def __rustq_source__, do: unquote(source)
    end
  end

  defp rust_module_mapping!(alias_ast, opts) do
    alias_parts = alias_parts!(alias_ast)
    rust_parts = opts |> Keyword.fetch!(:as) |> List.wrap()
    {alias_parts, rust_parts}
  end

  defp alias_parts!({:__aliases__, _, parts}), do: parts

  defp alias_parts!(atom) when is_atom(atom) do
    atom
    |> Module.split()
    |> Enum.map(&RustQ.Atom.identifier!/1)
  end

  defp alias_parts!(other) do
    raise ArgumentError, "expected alias in defrustmod, got: #{Macro.to_string(other)}"
  end

  defp rust_module_map(values), do: values |> List.wrap() |> Map.new()
end
