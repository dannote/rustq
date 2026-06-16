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

  defmacro __using__(_opts) do
    quote do
      import RustQ.Meta
      Module.register_attribute(__MODULE__, :rustq_defs, accumulate: true)
      @before_compile RustQ.Meta
    end
  end

  defmacro defrust(call_ast, do: body_ast) do
    {name, _meta, args} = call_ast
    arity = length(args || [])

    stub_args =
      if arity == 0, do: [], else: for(index <- 1..arity//1, do: Macro.var(:"_arg#{index}", nil))

    quote do
      @rustq_defs {unquote(Macro.escape(call_ast)), unquote(Macro.escape(body_ast))}
      def unquote(name)(unquote_splicing(stub_args)), do: :erlang.nif_error(:rustq_defrust_stub)
    end
  end

  defmacro __before_compile__(env) do
    defs = Module.get_attribute(env.module, :rustq_defs) |> List.wrap() |> Enum.reverse()
    specs = Module.get_attribute(env.module, :spec) |> List.wrap()
    type_aliases = env.module |> Module.get_attribute(:type) |> Type.type_aliases()

    asts = Enum.map(defs, &build_ast(&1, specs, type_aliases))
    type_items = build_type_items(type_aliases)
    function_items = Enum.map(asts, &validate_item_ast/1)
    items = type_items ++ function_items

    type_source = Enum.map_join(type_items, "\n\n", &Rust.to_fragment/1)
    function_source = Enum.map_join(asts, "\n\n", &AST.render_function_native/1)
    source = [type_source, function_source] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")

    quote do
      @doc false
      def __rustq_asts__, do: unquote(Macro.escape(asts))

      @doc false
      def __rustq_types__, do: unquote(Macro.escape(type_aliases))

      @doc false
      def __rustq_type_items__, do: unquote(Macro.escape(type_items))

      @doc false
      def __rustq_items__, do: unquote(Macro.escape(items))

      @doc false
      def __rustq_source__, do: unquote(source)
    end
  end

  defp build_ast({call_ast, body_ast}, specs, type_aliases) do
    {name, _meta, arg_asts} = call_ast
    arg_names = Enum.map(arg_asts, &arg_name!/1)
    {arg_types, return_type} = find_spec!(specs, name, length(arg_names), type_aliases)

    args = Enum.zip(arg_names, Enum.map(arg_types, & &1.ast))
    body = Lower.function_ast(body_ast, return_type, Map.new(Enum.zip(arg_names, arg_types)))
    lifetime = if Enum.any?(arg_types ++ [return_type], &String.contains?(&1.rust, "'a")), do: :a

    %AST.Function{
      name: name,
      args: args,
      returns: return_type.ast,
      body: body,
      lifetime: lifetime
    }
  end

  defp validate_item_ast(%AST.Function{} = item), do: validate_ast_item(item)
  defp validate_item_ast(%AST.Struct{} = item), do: validate_ast_item(item)
  defp validate_item_ast(%AST.Enum{} = item), do: validate_ast_item(item)

  defp validate_ast_item(item) do
    RustQ.parse_fragment!(:item, AST.render_item_native(item))
  end

  defp build_type_items(type_aliases) do
    type_aliases
    |> Map.values()
    |> Enum.flat_map(&type_items/1)
  end

  defp type_items(%Type{
         kind: :enum,
         rust: rust_name,
         meta: %{variants: variants, elixir_name: elixir_name}
       }) do
    enum =
      validate_item_ast(%AST.Enum{
        name: String.to_atom(rust_name),
        vis: :pub,
        derive: [:Clone, :Copy, :Debug, :Eq, :PartialEq],
        variants:
          variants
          |> Enum.map(&rust_variant/1)
          |> Enum.map(&%AST.EnumVariant{name: String.to_atom(&1)})
      })

    decoder =
      validate_item_ast(%AST.Function{
        name: String.to_atom("decode_#{elixir_name}_atom"),
        vis: :pub,
        args: [value: "Atom"],
        returns: %AST.TypeNifResult{inner: %AST.TypePath{parts: [rust_name]}},
        body: [
          %AST.Return{
            expr: %AST.Match{
              expr: %AST.Var{name: :value},
              arms:
                Enum.map(variants, fn variant ->
                  %AST.Arm{
                    pattern: %AST.PatAtomGuard{name: variant},
                    body: [
                      %AST.Return{
                        expr: %AST.Ok{
                          expr: %AST.Path{parts: [rust_name, rust_variant(variant)]}
                        }
                      }
                    ]
                  }
                end) ++
                  [
                    %AST.Arm{
                      pattern: %AST.PatWildcard{},
                      body: [
                        %AST.Return{
                          expr: %AST.Err{expr: %AST.Path{parts: [:rustler, :Error, :BadArg]}}
                        }
                      ]
                    }
                  ]
            }
          }
        ]
      })

    [enum, decoder]
  end

  defp type_items(%Type{kind: :tuple_enum, rust: rust_name, meta: %{variants: variants}}) do
    [
      validate_item_ast(%AST.Enum{
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
      })
    ]
  end

  defp type_items(%Type{kind: :struct, meta: %{rust_name: rust_name, fields: fields}}) do
    lifetime =
      if Enum.any?(fields, fn {_name, type, _presence} -> String.contains?(type.rust, "'a") end),
        do: :a

    [
      validate_item_ast(%AST.Struct{
        name: String.to_atom(rust_name),
        vis: :pub,
        derive: [:Clone, :Debug],
        lifetime: lifetime,
        fields: Enum.map(fields, &struct_field_ast/1)
      })
    ]
  end

  defp type_items(_type), do: []

  defp struct_field_ast({name, %Type{} = type, :required}) do
    %AST.StructField{name: name, type: type.ast, vis: :pub}
  end

  defp struct_field_ast({name, %Type{} = type, :optional}) do
    %AST.StructField{name: name, type: %AST.TypeOption{inner: type.ast}, vis: :pub}
  end

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
