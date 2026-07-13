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

  `defrustmacro` defines a small `macro_rules!` item from a Rusty-Elixir body.
  Its arguments are Rust macro fragments (`:expr` by default, with `:ty`
  supported for type arguments) while the body still uses ordinary Rusty-Elixir
  forms such as calls, `decode_as!/2`, and inference-backed propagation.

  Prefer `@spec` plus `defrust` for user-facing Rusty Elixir. Generated or
  external Rust paths should normally be expressed as ordinary remote types such
  as `GeneratedOpts.OvalOpts.t(R.lifetime(:a))`; use `RustQ.Type` markers such
  as `R.ref/1`, `R.nif_result/1`, `R.unit/0`, `R.slice/1`, and `R.lifetime/1`
  only where Elixir typespecs need Rust-specific precision. The internal
  `RustQ.Meta.AST` bridge is for generators that already hold RustQ AST
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
    * fallible calls in argument, return, case-scrutinee, `some(...)`,
      `decode_as!`, and many local-binding positions can infer Rust `?` from
      type metadata
    * `unwrap!(expression)` is the explicit spelling for Rust `expression?`;
      prefer inference when callable metadata is available
    * `ref(expression)` / `mut_ref(expression)` spell explicit Rust borrows;
      many ordinary calls infer borrows from expected argument types
    * `deref(expression)` spells Rust dereference and can propagate fallible
      reference access such as `args.first().ok_or(badarg())`
    * Option branching should use Elixir `case`, for example
      `case maybe do {:some, value} -> ...; :none -> ... end`; do not introduce
      Rust-shaped `if_let` syntax at the authoring layer

  Escape hatches such as `raw_expr!` remain low-level last resorts, not the
  normal way to reference project-owned Rust modules or types.
  """

  alias RustQ.Binding.Source
  alias RustQ.Meta.AST
  alias RustQ.Meta.Options
  alias RustQ.Meta.RustMacro
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST.Render
  alias RustQ.Rust.Identifier

  @doc false
  defmacro __using__(opts) do
    %{
      rust_sources: rust_sources,
      rust_packages: rust_packages,
      callable_modules: callable_modules,
      static_types: static_types
    } =
      Options.validate!(opts, __CALLER__)

    quote do
      import RustQ.Meta
      alias RustQ.Clippy, as: Clippy
      Module.register_attribute(__MODULE__, :rustq_defs, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_macros, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_mod_aliases, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_rust_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_rust_packages, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_callable_modules, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_static_types, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_current_rust_mod, accumulate: false)
      @rustq_rust_sources unquote(Macro.escape(List.wrap(rust_sources)))
      @rustq_rust_packages unquote(Macro.escape(List.wrap(rust_packages)))
      @rustq_callable_modules unquote(Macro.escape(List.wrap(callable_modules)))
      @rustq_static_types unquote(Macro.escape(List.wrap(static_types)))
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
      @doc false
      def unquote(name)(unquote_splicing(stub_args)), do: :erlang.nif_error(:rustq_defrust_stub)
    end
  end

  defmacro defrustmacro(call_ast, do: body_ast) do
    quote do
      @rustq_macros {unquote(Macro.escape(call_ast)), unquote(Macro.escape(body_ast)),
                     RustQ.Meta.Attrs.current_rust_mod(__MODULE__)}
    end
  end

  defmacro __before_compile__(env), do: build_before_compile(env)

  defp build_before_compile(env) do
    %{
      built_asts: built_asts,
      built_macros: built_macros,
      local_callables: local_callables,
      rust_macros: rust_macros,
      type_aliases: type_aliases
    } = compile_context(env)

    asts = Enum.map(built_asts, & &1.ast)
    macro_items = Enum.map(built_macros, &Map.take(&1, [:name, :ast, :rust_module]))
    type_asts = AST.build_type_asts(type_aliases)
    type_items = type_asts
    rust_items = AST.group_module_asts(built_macros ++ built_asts)
    items = type_items ++ rust_items

    type_source = Enum.map_join(type_items, "\n\n", &Render.render_item/1)

    function_source =
      Enum.map_join(rust_items, "\n\n", &Render.render_item/1)

    source = [type_source, function_source] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")

    exports(
      asts: asts,
      macro_items: macro_items,
      rust_macros: rust_macros,
      type_aliases: type_aliases,
      type_asts: type_asts,
      type_items: type_items,
      items: items,
      local_callables: local_callables,
      source: source
    )
  end

  defp exports(values) do
    definitions = [
      {:__rustq_asts__, values[:asts]},
      {:__rustq_macro_items__, values[:macro_items]},
      {:__rustq_macro_definitions__, values[:rust_macros]},
      {:__rustq_types__, values[:type_aliases]},
      {:__rustq_type_asts__, values[:type_asts]},
      {:__rustq_type_items__, values[:type_items]},
      {:__rustq_items__, values[:items]},
      {:__rustq_callables__, values[:local_callables]},
      {:__rustq_source__, values[:source]}
    ]

    {:__block__, [], Enum.map(definitions, &export_definition/1)}
  end

  defp export_definition({name, value}) do
    quote do
      @doc false
      def unquote(name)(), do: unquote(Macro.escape(value))
    end
  end

  defp compile_context(env) do
    defs = Module.get_attribute(env.module, :rustq_defs) |> List.wrap() |> Enum.reverse()
    macro_defs = Module.get_attribute(env.module, :rustq_macros) |> List.wrap() |> Enum.reverse()
    specs = Module.get_attribute(env.module, :spec) |> List.wrap()
    type_aliases = env.module |> Module.get_attribute(:type) |> Type.type_aliases()
    rust_modules = env.module |> Module.get_attribute(:rustq_mod_aliases) |> rust_module_map()
    local_callables = AST.callables_from_specs(specs, type_aliases)
    external_callables = Source.external_callables(env.module)

    external_static_types =
      Map.merge(
        Source.external_static_types(env.module),
        configured_static_types(env.module, type_aliases)
      )

    rust_macros = RustMacro.definitions(macro_defs)
    rust_macro_index = RustMacro.index!(rust_macros)
    callables = local_callables ++ external_callables

    %{
      built_asts:
        Enum.map(
          defs,
          &AST.build_ast(
            &1,
            specs,
            type_aliases,
            rust_modules,
            env,
            external_callables,
            external_static_types,
            rust_macro_index
          )
        ),
      built_macros: RustMacro.items(rust_macros, rust_modules, env, callables, rust_macro_index),
      local_callables: local_callables,
      rust_macros: rust_macros,
      type_aliases: type_aliases
    }
  end

  defp configured_static_types(module, type_aliases) do
    module
    |> Module.get_attribute(:rustq_static_types)
    |> List.wrap()
    |> List.flatten()
    |> Map.new(fn {name, type_ast} -> {name, RustQ.Spec.type(type_ast, type_aliases)} end)
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
    |> Enum.map(&Identifier.atom!/1)
  end

  defp alias_parts!(other) do
    raise ArgumentError, "expected alias in defrustmod, got: #{Macro.to_string(other)}"
  end

  defp rust_module_map(values), do: values |> List.wrap() |> Map.new()
end
