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
  only where Elixir typespecs need Rust-specific precision. `RustQ.Meta.AST.quoted/2`
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

  alias RustQ.Binding.Callable
  alias RustQ.Meta.AST
  alias RustQ.Meta.Type
  alias RustQ.Meta.Validate
  alias RustQ.Rust
  alias RustQ.Rust.AST, as: RustAST
  alias RustQ.Rust.AST.Render
  alias RustQ.Syn

  @doc false
  defmacro __using__(opts) do
    rust_sources = Keyword.get(opts, :rust_sources, [])
    rust_packages = Keyword.get(opts, :rust_packages, [])

    callable_modules =
      opts
      |> Keyword.get(:callable_modules, [])
      |> List.wrap()
      |> Enum.map(&Macro.expand(&1, __CALLER__))

    quote do
      import RustQ.Meta
      Module.register_attribute(__MODULE__, :rustq_defs, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_mod_aliases, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_rust_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_rust_packages, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_callable_modules, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_current_rust_mod, accumulate: false)
      @rustq_rust_sources unquote(Macro.escape(List.wrap(rust_sources)))
      @rustq_rust_packages unquote(Macro.escape(List.wrap(rust_packages)))
      @rustq_callable_modules unquote(Macro.escape(List.wrap(callable_modules)))
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

    local_callables = AST.callables_from_specs(specs, type_aliases)
    external_callables = external_callables(env.module)
    callables = local_callables ++ external_callables

    built_asts =
      Enum.map(
        defs,
        &AST.build_ast(&1, specs, type_aliases, rust_modules, env, external_callables)
      )

    asts = Enum.map(built_asts, & &1.ast)
    type_asts = AST.build_type_asts(type_aliases)
    type_items = Enum.map(type_asts, &Validate.item_ast/1)
    rust_items = AST.group_module_asts(built_asts)
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
      def __rustq_callables__, do: unquote(Macro.escape(callables))

      @doc false
      def __rustq_source__, do: unquote(source)
    end
  end

  defp external_callables(module) do
    rust_source_callables_for_module(module) ++
      rust_package_callables_for_module(module) ++
      callable_module_callables(module)
  end

  defp rust_source_callables_for_module(module) do
    module
    |> Module.get_attribute(:rustq_rust_sources)
    |> List.wrap()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&rust_source_callables/1)
  end

  defp callable_module_callables(module) do
    module
    |> Module.get_attribute(:rustq_callable_modules)
    |> List.wrap()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(fn callable_module ->
      if Code.ensure_loaded?(callable_module) and
           function_exported?(callable_module, :__rustq_callables__, 0) do
        callable_module.__rustq_callables__()
      else
        []
      end
    end)
  end

  defp rust_source_callables(path) do
    file = Syn.parse_file!(path)

    function_callables = file |> Syn.functions() |> Enum.map(&Callable.from_syn_function/1)
    method_callables = file |> Syn.impls() |> Enum.flat_map(&impl_callables/1)

    function_callables ++ method_callables
  end

  defp rust_package_callables_for_module(module) do
    module
    |> Module.get_attribute(:rustq_rust_packages)
    |> List.wrap()
    |> List.flatten()
    |> Enum.flat_map(&rust_package_callables/1)
  end

  defp rust_package_callables({package, opts}) when is_binary(package) and is_list(opts) do
    index = Syn.Index.cached_package(package, opts)

    index
    |> Syn.Index.impls()
    |> Enum.flat_map(&impl_callables/1)
    |> Enum.map(&normalize_callable_public_aliases(&1, index))
  end

  defp rust_package_callables(package) when is_binary(package),
    do: rust_package_callables({package, []})

  defp impl_callables(%Syn.Impl{} = impl) do
    Enum.map(impl.methods, &Callable.from_syn_method(&1, target: impl.target))
  end

  defp normalize_callable_public_aliases(%Callable{} = callable, %Syn.Index{} = index) do
    %{
      callable
      | args: Enum.map(callable.args, &normalize_callable_arg(&1, index)),
        returns: normalize_public_alias_type(callable.returns, index)
    }
  end

  defp normalize_callable_arg(%{type: type} = arg, index),
    do: %{arg | type: normalize_public_alias_type(type, index)}

  defp normalize_public_alias_type(%Type{kind: :type, meta: %{syn_name: name}} = type, index)
       when is_binary(name) do
    case Syn.Index.public_type_name(index, name) do
      {:ok, public_name} when public_name != name ->
        %{
          type
          | rust: public_name,
            ast: %RustAST.TypePath{parts: [RustQ.Atom.identifier!(public_name)]}
        }

      _missing_or_same ->
        type
    end
  end

  defp normalize_public_alias_type(%Type{} = type, _index), do: type
  defp normalize_public_alias_type(nil, _index), do: nil

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
