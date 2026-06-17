defmodule RustQ.Meta do
  @moduledoc """
  Valid-Elixir macro frontend for generating RustQ Rust fragments.

  `defrust` captures a normal Elixir function-shaped body plus its preceding
  `@spec`, lowers that quoted Elixir AST to Rust, and exposes generated Rust
  items through `__rustq_items__/0` and `__rustq_source__/0`.
  """

  alias RustQ.Meta.Lower
  alias RustQ.Meta.Type
  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  require A

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
                   RustQ.Meta.__take_pending_attrs__(__MODULE__),
                   RustQ.Meta.__current_rust_mod__(__MODULE__)}
      def unquote(name)(unquote_splicing(stub_args)), do: :erlang.nif_error(:rustq_defrust_stub)
    end
  end

  defmacro __before_compile__(env) do
    defs = Module.get_attribute(env.module, :rustq_defs) |> List.wrap() |> Enum.reverse()
    specs = Module.get_attribute(env.module, :spec) |> List.wrap()
    type_aliases = env.module |> Module.get_attribute(:type) |> Type.type_aliases()
    rust_modules = env.module |> Module.get_attribute(:rustq_mod_aliases) |> rust_module_map()

    built_asts = Enum.map(defs, &build_ast(&1, specs, type_aliases, rust_modules))
    asts = Enum.map(built_asts, & &1.ast)
    type_asts = build_type_asts(type_aliases)
    type_items = Enum.map(type_asts, &validate_item_ast/1)
    function_asts = group_module_asts(built_asts)
    function_items = Enum.map(function_asts, &validate_item_ast/1)
    items = type_items ++ function_items

    type_source = Enum.map_join(type_items, "\n\n", &Rust.to_fragment/1)

    function_source =
      Enum.map_join(function_asts, "\n\n", &RustQ.Rust.AST.Render.render_item_native/1)

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

  def __take_pending_attrs__(module), do: pending_attrs(module)
  def __current_rust_mod__(module), do: Module.get_attribute(module, :rustq_current_rust_mod)

  defp rust_module_mapping!(alias_ast, opts) do
    alias_parts = alias_parts!(alias_ast)
    rust_parts = opts |> Keyword.fetch!(:as) |> List.wrap()
    {alias_parts, rust_parts}
  end

  defp alias_parts!({:__aliases__, _, parts}), do: parts

  defp alias_parts!(atom) when is_atom(atom) do
    atom
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  end

  defp alias_parts!(other) do
    raise ArgumentError, "expected alias in defrustmod, got: #{Macro.to_string(other)}"
  end

  defp rust_module_map(values), do: values |> List.wrap() |> Map.new()

  @spec function_ast(
          atom(),
          [{atom(), Type.t() | Macro.t()}],
          Type.t() | Macro.t(),
          Macro.t(),
          keyword()
        ) ::
          AST.Function.t()
  def function_ast(name, args, return_type, body_ast, opts \\ []) do
    type_aliases = Keyword.get(opts, :type_aliases, %{})
    arg_names = Enum.map(args, &elem(&1, 0))
    arg_types = Enum.map(args, fn {_name, type} -> normalize_type(type, type_aliases) end)
    return_type = normalize_type(return_type, type_aliases)

    function_args =
      Enum.zip(arg_names, Enum.map(arg_types, & &1.ast))
      |> Enum.map(fn {name, type} -> %AST.FunctionArg{name: name, type: type} end)

    body =
      Lower.function_ast(body_ast, return_type, Map.new(Enum.zip(arg_names, arg_types)),
        rust_modules: Keyword.get(opts, :rust_modules, %{})
      )

    lifetime =
      Keyword.get_lazy(opts, :lifetime, fn ->
        if Enum.any?(arg_types ++ [return_type], &String.contains?(&1.rust, "'a")), do: :a
      end)

    %AST.Function{
      name: name,
      args: function_args,
      returns: return_type.ast,
      body: body,
      lifetime: lifetime,
      vis: Keyword.get(opts, :vis),
      attrs: Keyword.get(opts, :attrs, [])
    }
  end

  defp normalize_type(%Type{} = type, _aliases), do: type
  defp normalize_type(type_ast, aliases), do: Type.from_spec_ast(type_ast, aliases)

  defp pending_attrs(module) do
    nif = Module.get_attribute(module, :nif)
    allow = Module.get_attribute(module, :allow) |> List.wrap() |> Enum.reverse()
    Module.delete_attribute(module, :nif)
    Module.delete_attribute(module, :allow)

    []
    |> add_nif_attr(nif)
    |> Kernel.++(Enum.map(allow, &allow_attr/1))
  end

  defp add_nif_attr(attrs, nil), do: attrs
  defp add_nif_attr(attrs, false), do: attrs
  defp add_nif_attr(attrs, true), do: attrs ++ [%AST.Attribute{path: [:rustler, :nif]}]

  defp add_nif_attr(attrs, opts) when is_list(opts),
    do: attrs ++ [%AST.Attribute{path: [:rustler, :nif], args: opts}]

  defp allow_attr(values), do: %AST.Attribute{path: [:allow], args: List.wrap(values)}

  defp build_ast({call_ast, body_ast}, specs, type_aliases, rust_modules),
    do: build_ast({call_ast, body_ast, [], nil}, specs, type_aliases, rust_modules)

  defp build_ast({call_ast, body_ast, attrs}, specs, type_aliases, rust_modules),
    do: build_ast({call_ast, body_ast, attrs, nil}, specs, type_aliases, rust_modules)

  defp build_ast({call_ast, body_ast, attrs, rust_module}, specs, type_aliases, rust_modules) do
    {name, _meta, arg_asts} = call_ast
    arg_names = Enum.map(arg_asts, &arg_name!/1)
    {arg_types, return_type} = find_spec!(specs, name, length(arg_names), type_aliases)

    args =
      Enum.zip(arg_names, Enum.map(arg_types, & &1.ast))
      |> Enum.map(fn {name, type} -> %AST.FunctionArg{name: name, type: type} end)

    body =
      Lower.function_ast(body_ast, return_type, Map.new(Enum.zip(arg_names, arg_types)),
        rust_modules: rust_modules
      )

    lifetime = if Enum.any?(arg_types ++ [return_type], &String.contains?(&1.rust, "'a")), do: :a

    ast = %AST.Function{
      name: name,
      args: args,
      returns: return_type.ast,
      body: body,
      lifetime: lifetime,
      attrs: attrs
    }

    %{ast: ast, rust_module: rust_module}
  end

  defp group_module_asts(built_asts) do
    {plain, nested} = Enum.split_with(built_asts, &is_nil(&1.rust_module))

    plain_items = Enum.map(plain, & &1.ast)

    nested_items =
      nested
      |> Enum.group_by(& &1.rust_module, & &1.ast)
      |> Enum.map(fn {module, items} -> %AST.Module{name: List.last(module), items: items} end)

    plain_items ++ nested_items
  end

  defp validate_item_ast(%AST.Function{} = item), do: validate_ast_item(item)
  defp validate_item_ast(%AST.Module{} = item), do: validate_ast_item(item)
  defp validate_item_ast(%AST.Impl{} = item), do: validate_ast_item(item)
  defp validate_item_ast(%AST.Struct{} = item), do: validate_ast_item(item)
  defp validate_item_ast(%AST.Enum{} = item), do: validate_ast_item(item)

  defp validate_ast_item(item) do
    RustQ.parse_fragment!(:item, RustQ.Rust.AST.Render.render_item_native(item))
  end

  defp build_type_asts(type_aliases) do
    type_aliases
    |> Map.values()
    |> Enum.flat_map(&type_items/1)
  end

  defp type_items(%Type{
         kind: :enum,
         rust: rust_name,
         meta: %{variants: variants, elixir_name: elixir_name}
       }) do
    enum = %AST.Enum{
      name: String.to_atom(rust_name),
      vis: :pub,
      derive: [:Clone, :Copy, :Debug, :Eq, :PartialEq],
      variants:
        variants
        |> Enum.map(&rust_variant/1)
        |> Enum.map(&%AST.EnumVariant{name: String.to_atom(&1)})
    }

    decoder = %AST.Function{
      name: String.to_atom("decode_#{elixir_name}_atom"),
      vis: :pub,
      args: [%AST.FunctionArg{name: :value, type: "Atom"}],
      returns: %AST.TypeNifResult{inner: %AST.TypePath{parts: [rust_name]}},
      body:
        A.block do
          A.return do
            A.match A.var(:value) do
              Enum.map(variants, fn variant ->
                A.arm %AST.PatAtomGuard{name: variant} do
                  A.return(A.ok(A.path([rust_name, rust_variant(variant)])))
                end
              end) ++
                [
                  A.arm A.wildcard() do
                    A.return(A.err(A.path([:rustler, :Error, :BadArg])))
                  end
                ]
            end
          end
        end
    }

    [enum, decoder]
  end

  defp type_items(%Type{
         kind: :tuple_enum,
         rust: rust_name,
         meta: %{elixir_name: elixir_name, variants: variants}
       }) do
    enum = %AST.Enum{
      name: String.to_atom(rust_name),
      vis: :pub,
      derive: [:Clone, :Debug],
      variants:
        Enum.map(variants, fn {tag, types} ->
          %AST.EnumVariant{
            name: tag |> rust_variant() |> String.to_atom(),
            tuple: Enum.map(types, & &1.ast)
          }
        end)
    }

    decoder = %AST.Function{
      name: String.to_atom("decode_#{elixir_name}"),
      vis: :pub,
      args: [%AST.FunctionArg{name: :term, type: %AST.TypePath{parts: [:Term], lifetimes: [:a]}}],
      returns: %AST.TypeNifResult{inner: %AST.TypePath{parts: [rust_name]}},
      lifetime: :a,
      body: tuple_enum_decoder_body(rust_name, variants)
    }

    [enum, decoder]
  end

  defp type_items(%Type{kind: :struct, meta: %{rust_name: rust_name, fields: fields}}) do
    lifetime =
      if Enum.any?(fields, fn {_name, type, _presence} -> String.contains?(type.rust, "'a") end),
        do: :a

    struct = %AST.Struct{
      name: String.to_atom(rust_name),
      vis: :pub,
      derive: [:Clone, :Debug],
      lifetime: lifetime,
      fields: Enum.map(fields, &struct_field_ast/1)
    }

    decoder = %AST.Function{
      name: String.to_atom("decode_#{Macro.underscore(rust_name)}"),
      vis: :pub,
      args: [%AST.FunctionArg{name: :term, type: %AST.TypePath{parts: [:Term], lifetimes: [:a]}}],
      returns: %AST.TypeNifResult{
        inner: %AST.TypePath{parts: [rust_name], lifetimes: List.wrap(lifetime)}
      },
      lifetime: :a,
      body:
        A.block do
          A.return(A.ok(A.struct([rust_name], Enum.map(fields, &struct_decoder_field/1))))
        end
    }

    [struct, decoder]
  end

  defp type_items(_type), do: []

  defp struct_field_ast({name, %Type{} = type, :required}) do
    %AST.StructField{name: name, type: type.ast, vis: :pub}
  end

  defp struct_field_ast({name, %Type{} = type, :optional}) do
    %AST.StructField{name: name, type: %AST.TypeOption{inner: type.ast}, vis: :pub}
  end

  defp struct_decoder_field({name, _type, :required}) do
    {name, A.try(A.method(A.try(A.method(:term, :map_get, [atom_call(name)])), :decode))}
  end

  defp struct_decoder_field({name, _type, :optional}) do
    {name,
     A.match A.method(:term, :map_get, [atom_call(name)]) do
       A.arm A.ok_pat(:value) do
         A.return(A.some(A.try(A.method(:value, :decode))))
       end

       A.arm A.err_pat(A.wildcard()) do
         A.return(A.none())
       end
     end}
  end

  defp tuple_enum_decoder_body(rust_name, variants) do
    A.block do
      A.let(:struct_name, struct_name_expr())

      A.return do
        A.match A.method(:struct_name, :as_str) do
          Enum.map(variants, fn {tag, [%Type{meta: %{rust_name: variant_name}}]} ->
            A.arm A.lit_pat("Elixir.#{variant_name}") do
              A.return do
                A.method(
                  A.call(String.to_atom("decode_#{Macro.underscore(variant_name)}"), [:term]),
                  :map,
                  [A.path([rust_name, rust_variant(tag)])]
                )
              end
            end
          end) ++
            [
              A.arm A.wildcard() do
                A.return(A.err(A.path([:rustler, :Error, :BadArg])))
              end
            ]
        end
      end
    end
  end

  defp struct_name_expr do
    A.try(A.method(A.try(A.method(:term, :map_get, [struct_atom_expr()])), :atom_to_string))
  end

  defp struct_atom_expr do
    A.try(A.path_call([:rustler, :Atom, :from_str], [A.method(:term, :get_env), "__struct__"]))
  end

  defp atom_call(name), do: A.path_call([:atoms, name])

  defp rust_variant(value), do: value |> Atom.to_string() |> Macro.camelize()

  defp arg_name!({name, _meta, context}) when is_atom(name) and is_atom(context), do: name

  defp arg_name!(other) do
    raise ArgumentError, "unsupported defrust argument: #{Macro.to_string(other)}"
  end

  defp find_spec!(specs, name, arity, type_aliases) do
    Enum.find_value(specs, fn
      {:spec, {:"::", _, [{^name, _, args}, return]}, _location} when length(args) == arity ->
        {Enum.map(args, &Type.from_spec_ast(&1, type_aliases)),
         Type.from_spec_ast(return, type_aliases)}

      _other ->
        nil
    end) ||
      raise ArgumentError,
            "missing @spec for defrust #{name}/#{arity}; define @spec immediately before or before defrust"
  end
end
