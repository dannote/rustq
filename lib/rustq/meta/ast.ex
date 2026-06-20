defmodule RustQ.Meta.Ast do
  @moduledoc false

  alias RustQ.Diagnostic
  alias RustQ.Meta.Decoder
  alias RustQ.Meta.Lower
  alias RustQ.Meta.Type
  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.Render

  require A

  @doc false
  @spec item(module(), atom()) :: Rust.Fragment.t()
  def item(module, name) when is_atom(module) and is_atom(name) do
    module
    |> ast!(name)
    |> Rust.ast_item()
  end

  @doc false
  @spec items(module(), [atom()]) :: [Rust.Fragment.t()]
  def items(module, names) when is_atom(module) and is_list(names),
    do: Enum.map(names, &item(module, &1))

  @doc false
  @spec ast!(module(), atom()) :: AST.Function.t()
  def ast!(module, name) when is_atom(module) and is_atom(name) do
    Enum.find(module.__rustq_asts__(), &(&1.name == name)) ||
      raise ArgumentError, "#{inspect(module)} has no defrust item named #{name}"
  end

  @doc false
  @spec quoted(atom(), keyword()) :: AST.Function.t()
  def quoted(name, opts) do
    args = Keyword.fetch!(opts, :args)
    return_type = Keyword.fetch!(opts, :returns)
    body_ast = Keyword.fetch!(opts, :do)
    type_aliases = Keyword.get(opts, :type_aliases, %{})
    arg_names = Enum.map(args, &elem(&1, 0))
    arg_types = Enum.map(args, fn {_name, type} -> normalize_type(type, type_aliases) end)
    return_type = normalize_type(return_type, type_aliases)

    function_args =
      Enum.zip(arg_names, Enum.map(arg_types, & &1.ast))
      |> Enum.map(fn {name, type} -> %AST.FunctionArg{name: name, type: type} end)

    body =
      Lower.quoted_body(body_ast, return_type, Map.new(Enum.zip(arg_names, arg_types)),
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

  def build_ast({call_ast, body_ast}, specs, type_aliases, rust_modules, env),
    do: build_ast({call_ast, body_ast, [], nil}, specs, type_aliases, rust_modules, env)

  def build_ast({call_ast, body_ast, attrs}, specs, type_aliases, rust_modules, env),
    do: build_ast({call_ast, body_ast, attrs, nil}, specs, type_aliases, rust_modules, env)

  def build_ast({call_ast, body_ast, attrs, rust_module}, specs, type_aliases, rust_modules, env) do
    do_build_ast({call_ast, body_ast, attrs, rust_module}, specs, type_aliases, rust_modules, env)
  rescue
    error in Diagnostic.Error ->
      raise_defrust_diagnostic(call_ast, body_ast, error.diagnostic)

    error in [ArgumentError, FunctionClauseError] ->
      raise_defrust_diagnostic(call_ast, body_ast, error)
  end

  def build_type_asts(type_aliases) do
    type_aliases
    |> Map.values()
    |> Enum.flat_map(&type_items/1)
  end

  def group_module_asts(built_asts) do
    {plain, nested} = Enum.split_with(built_asts, &is_nil(&1.rust_module))

    plain_items = Enum.map(plain, & &1.ast)

    nested_items =
      nested
      |> Enum.group_by(& &1.rust_module, & &1.ast)
      |> Enum.map(fn {module, items} -> %AST.Module{name: List.last(module), items: items} end)

    plain_items ++ nested_items
  end

  defp normalize_type(%Type{} = type, _aliases), do: type
  defp normalize_type(type_ast, _aliases) when is_binary(type_ast), do: rust_ast_type(type_ast)

  defp normalize_type(%{__struct__: _module} = type_ast, _aliases) do
    if AST.type_node?(type_ast) do
      rust_ast_type(type_ast)
    else
      raise ArgumentError, "expected RustQ type AST node, got: #{inspect(type_ast)}"
    end
  end

  defp normalize_type(type_ast, aliases), do: Type.parse(type_ast, aliases)

  defp rust_ast_type(type_ast) do
    %Type{
      kind: rust_ast_type_kind(type_ast),
      rust: type_ast |> Render.render_type() |> IO.iodata_to_binary(),
      ast: type_ast
    }
  end

  defp rust_ast_type_kind(%AST.TypeNifResult{}), do: :nif_result
  defp rust_ast_type_kind(%AST.TypeResult{}), do: :result
  defp rust_ast_type_kind(%AST.TypeOption{}), do: :option
  defp rust_ast_type_kind(%AST.TypeUnit{}), do: :unit
  defp rust_ast_type_kind(_type_ast), do: :type

  defp do_build_ast(
         {call_ast, body_ast, attrs, rust_module},
         specs,
         type_aliases,
         rust_modules,
         env
       ) do
    {name, _meta, arg_asts} = call_ast
    arg_names = Enum.map(arg_asts, &arg_name!/1)
    {arg_types, return_type} = find_spec!(specs, name, length(arg_names), type_aliases)

    args =
      Enum.zip(arg_names, Enum.map(arg_types, & &1.ast))
      |> Enum.map(fn {name, type} -> %AST.FunctionArg{name: name, type: type} end)

    body_ast = expand_body_macros(body_ast, env)

    body =
      Lower.quoted_body(body_ast, return_type, Map.new(Enum.zip(arg_names, arg_types)),
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

  @spec raise_defrust_diagnostic(Macro.t(), Macro.t(), Exception.t() | Diagnostic.t()) ::
          no_return()
  defp raise_defrust_diagnostic(call_ast, body_ast, cause) do
    {name, _meta, arg_asts} = call_ast
    arity = length(arg_asts || [])

    Diagnostic.defrust(
      :build_failed,
      body_ast,
      "failed to build defrust #{name}/#{arity}: #{diagnostic_cause_message(cause)}",
      details: %{function: name, arity: arity, cause: cause}
    )
  end

  defp diagnostic_cause_message(%Diagnostic{} = diagnostic), do: diagnostic.message
  defp diagnostic_cause_message(error), do: Exception.message(error)

  defp expand_body_macros(body_ast, env) do
    body_ast
    |> Macro.prewalk(fn ast -> expand_body_macro(ast, env) end)
    |> flatten_blocks()
  end

  defp expand_body_macro({name, _meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if kernel_or_rusty_form?(name) do
      ast
    else
      expanded = Macro.expand(ast, env)

      if expanded == ast do
        ast
      else
        expand_body_macros(expanded, env)
      end
    end
  end

  defp expand_body_macro(ast, _env), do: ast

  defp flatten_blocks({:__block__, meta, expressions}) do
    {:__block__, meta, Enum.flat_map(expressions, &flatten_block_expression/1)}
  end

  defp flatten_blocks(ast), do: ast

  defp flatten_block_expression({:__block__, _meta, expressions}),
    do: Enum.flat_map(expressions, &flatten_block_expression/1)

  defp flatten_block_expression(expression), do: [expression]

  defp kernel_or_rusty_form?(name) do
    name in [
      :=,
      :!,
      :!=,
      :!==,
      :%,
      :{},
      :*,
      :+,
      :++,
      :-,
      :--,
      :/,
      :|>,
      :<,
      :<=,
      :==,
      :===,
      :=~,
      :>,
      :>=,
      :__aliases__,
      :__block__,
      :and,
      :case,
      :cast,
      :fn,
      :for,
      :if,
      :in,
      :is_nil,
      :not,
      :or,
      :ref,
      :mut_ref,
      :deref,
      :expr!,
      :pat!,
      :stmt!,
      :arm!,
      :raw_expr!,
      :raw_pat!,
      :raw_stmt!,
      :raw_arm!,
      :unwrap!
    ]
  end

  defp type_items(%Type{
         kind: :enum,
         rust: rust_name,
         meta: %{variants: variants, elixir_name: elixir_name}
       }) do
    enum = %AST.Enum{
      name: RustQ.Atom.identifier!(rust_name),
      vis: :pub,
      derive: [:Clone, :Copy, :Debug, :Eq, :PartialEq],
      variants:
        variants
        |> Enum.map(&Decoder.rust_variant/1)
        |> Enum.map(&%AST.EnumVariant{name: RustQ.Atom.identifier!(&1)})
    }

    decoder = %AST.Function{
      name: RustQ.Atom.identifier!("decode_#{elixir_name}_atom"),
      vis: :pub,
      args: [%AST.FunctionArg{name: :value, type: "Atom"}],
      returns: %AST.TypeNifResult{inner: %AST.TypePath{parts: [rust_name]}},
      body:
        A.block do
          A.return do
            A.match A.var(:value) do
              Enum.map(variants, fn variant ->
                A.arm %AST.PatAtomGuard{name: variant} do
                  A.return(A.ok(A.path([rust_name, Decoder.rust_variant(variant)])))
                end
              end) ++ [A.badarg_arm()]
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
      name: RustQ.Atom.identifier!(rust_name),
      vis: :pub,
      derive: [:Clone, :Debug],
      variants:
        Enum.map(variants, fn {tag, types} ->
          %AST.EnumVariant{
            name: tag |> Decoder.rust_variant() |> RustQ.Atom.identifier!(),
            tuple: Enum.map(types, & &1.ast)
          }
        end)
    }

    decoder = %AST.Function{
      name: RustQ.Atom.identifier!("decode_#{elixir_name}"),
      vis: :pub,
      args: [%AST.FunctionArg{name: :term, type: %AST.TypePath{parts: [:Term], lifetimes: [:a]}}],
      returns: %AST.TypeNifResult{inner: %AST.TypePath{parts: [rust_name]}},
      lifetime: :a,
      body: Decoder.tuple_enum_decoder_body(rust_name, variants)
    }

    [enum, decoder]
  end

  defp type_items(%Type{kind: :struct, meta: %{rust_name: rust_name, fields: fields}}) do
    lifetime =
      if Enum.any?(fields, fn {_name, type, _presence} -> String.contains?(type.rust, "'a") end),
        do: :a

    struct = %AST.Struct{
      name: RustQ.Atom.identifier!(rust_name),
      vis: :pub,
      derive: [:Clone, :Debug],
      lifetime: lifetime,
      fields: Enum.map(fields, &Decoder.struct_field_ast/1)
    }

    decoder = %AST.Function{
      name: RustQ.Atom.identifier!("decode_#{Macro.underscore(rust_name)}"),
      vis: :pub,
      args: [%AST.FunctionArg{name: :term, type: %AST.TypePath{parts: [:Term], lifetimes: [:a]}}],
      returns: %AST.TypeNifResult{
        inner: %AST.TypePath{parts: [rust_name], lifetimes: List.wrap(lifetime)}
      },
      lifetime: :a,
      body:
        A.block do
          A.return(A.ok(A.struct([rust_name], Enum.map(fields, &Decoder.struct_decoder_field/1))))
        end
    }

    [struct, decoder]
  end

  defp type_items(_type), do: []

  defp arg_name!({name, _meta, context}) when is_atom(name) and is_atom(context), do: name

  defp arg_name!(other) do
    raise ArgumentError, "unsupported defrust argument: #{Macro.to_string(other)}"
  end

  defp find_spec!(specs, name, arity, type_aliases) do
    Enum.find_value(specs, fn
      {:spec, {:"::", _, [{^name, _, args}, return]}, _location} when length(args) == arity ->
        {Enum.map(args, &Type.parse(&1, type_aliases)), Type.parse(return, type_aliases)}

      _other ->
        nil
    end) ||
      raise ArgumentError,
            "missing @spec for defrust #{name}/#{arity}; define @spec immediately before or before defrust"
  end
end
