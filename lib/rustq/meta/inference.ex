defmodule RustQ.Meta.Inference do
  @moduledoc """
  Performs block-local type inference used by Rusty-Elixir lowering.

  This module intentionally stays scoped to straight-line block inference. It
  propagates expected argument types from later callable uses back to earlier
  local let bindings and carries known let RHS types forward so receiver method
  calls can participate in the same pass.
  """

  alias RustQ.Meta.Pattern
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  @type callbacks :: %{
          required(:return_type) => (Macro.t() -> Type.t() | nil),
          required(:local_argument_types) => (atom(), non_neg_integer() -> [Type.t()] | nil),
          required(:path_argument_types) => ([atom()], atom(), non_neg_integer() ->
                                               [Type.t()] | nil),
          required(:method_argument_types) => (Type.t() | nil, atom(), non_neg_integer() ->
                                                 [Type.t()] | nil),
          required(:target_type) => (Type.t() | nil -> term()),
          required(:method_receiver_type) => (atom(), non_neg_integer() -> Type.t() | nil),
          optional(:block_return_type) => Type.t() | nil
        }

  @spec infer_downstream_let_types([Macro.t()], map(), callbacks()) :: map()
  def infer_downstream_let_types(expressions, vars, callbacks) when is_list(expressions) do
    expressions
    |> Stream.with_index()
    |> Enum.reduce({%{}, vars}, fn {expression, index}, {inferred, known_vars} ->
      new_inferred =
        infer_downstream_let_type(expression, expressions, index, known_vars, callbacks)

      next_known_vars =
        Map.merge(known_vars, inferred_binding_types(expression, new_inferred, callbacks))

      {Map.merge(inferred, new_inferred), next_known_vars}
    end)
    |> elem(0)
  end

  defp infer_downstream_let_type(
         {:=, _, [{name, _, context}, rhs]},
         expressions,
         index,
         vars,
         callbacks
       )
       when is_atom(name) and is_atom(context) do
    rhs_success_type = rhs_success_type(rhs, callbacks)

    expressions
    |> Enum.drop(index + 1)
    |> Enum.find_value(&expected_type_for_var(name, &1, vars, callbacks, rhs_success_type))
    |> case do
      %Type{} = type -> %{name => type}
      nil -> %{}
    end
  end

  defp infer_downstream_let_type(_expression, _expressions, _index, _vars, _callbacks), do: %{}

  defp inferred_binding_types({:=, _, [{name, _, context}, rhs]}, inferred, callbacks)
       when is_atom(name) and is_atom(context) do
    case Map.fetch(inferred, name) do
      {:ok, %Type{} = type} -> %{name => type}
      :error -> inferred_binding_type_from_rhs(name, rhs, callbacks)
    end
  end

  defp inferred_binding_types(_expression, _inferred, _callbacks), do: %{}

  defp inferred_binding_type_from_rhs(name, {:unwrap!, _, [call]}, callbacks) do
    case callbacks.return_type.(call) do
      %Type{} = type -> %{name => Type.inner(type) || type}
      nil -> %{}
    end
  end

  defp inferred_binding_type_from_rhs(name, call, callbacks) do
    case callbacks.return_type.(call) do
      %Type{} = type -> %{name => type}
      nil -> %{}
    end
  end

  defp rhs_success_type({:unwrap!, _, [call]}, callbacks), do: rhs_success_type(call, callbacks)

  defp rhs_success_type(call, %{return_type: return_type}) when is_function(return_type, 1) do
    case return_type.(call) do
      %Type{} = type -> Type.inner(type)
      nil -> nil
    end
  end

  defp rhs_success_type(_call, _callbacks), do: nil

  defp expected_type_for_var(name, ast, vars, callbacks, rhs_success_type) do
    call_expected_type =
      ast
      |> downstream_call_arg_types(vars, callbacks)
      |> Enum.find_value(fn {args, expected_types} ->
        expected_type_for_arg(name, args, expected_types)
      end)

    call_expected_type || expected_comparison_type_for_var(name, ast, rhs_success_type) ||
      expected_receiver_type_for_var(name, ast, callbacks, rhs_success_type) ||
      expected_return_type_for_var(name, ast, callbacks[:block_return_type])
  end

  defp expected_comparison_type_for_var(name, ast, %Type{} = rhs_success_type) do
    {_ast, comparisons} = Macro.prewalk(ast, [], &collect_var_comparison(&1, &2, name))

    case comparisons do
      [_ | _] -> rhs_success_type
      [] -> nil
    end
  end

  defp expected_comparison_type_for_var(_name, _ast, _rhs_success_type), do: nil

  defp collect_var_comparison({op, _meta, [left, right]} = ast, comparisons, name)
       when op in [:==, :!=, :<, :>, :<=, :>=] do
    if var_expr?(left, name) or var_expr?(right, name) do
      {ast, [op | comparisons]}
    else
      {ast, comparisons}
    end
  end

  defp collect_var_comparison(ast, comparisons, _name), do: {ast, comparisons}

  defp var_expr?({name, _meta, context}, name) when is_atom(context), do: true
  defp var_expr?(_expr, _name), do: false

  defp expected_type_for_arg(name, args, expected_types)
       when is_list(args) and is_list(expected_types) do
    args
    |> Enum.zip(expected_types)
    |> Enum.find_value(fn {arg, expected_type} ->
      expected_type_for_arg_expr(name, arg, expected_type)
    end)
  end

  defp expected_type_for_arg(_name, _args, _expected_types), do: nil

  defp expected_type_for_arg_expr(name, {var_name, _, context}, %Type{} = type)
       when name == var_name and is_atom(context),
       do: Type.into_iterator_vec(type) || Type.ref_inner(type) || type

  defp expected_type_for_arg_expr(
         name,
         {{:., _, [{var_name, _, context}, :as_ref]}, _meta, []},
         %Type{} = type
       )
       when name == var_name and is_atom(context),
       do: receiver_type_for_as_ref_argument(type)

  defp expected_type_for_arg_expr(
         name,
         {{:., _, [{var_name, _, context}, :as_slice]}, _meta, []},
         %Type{} = type
       )
       when name == var_name and is_atom(context),
       do: receiver_type_for_as_slice_argument(type)

  defp expected_type_for_arg_expr(name, {:ref, _meta, [arg]}, %Type{} = type) do
    case Type.ref_inner(type) do
      %Type{} = inner -> expected_type_for_arg_expr(name, arg, inner)
      nil -> expected_type_for_arg_expr(name, arg, Type.expected_value(type))
    end
  end

  defp expected_type_for_arg_expr(name, tuple, %Type{} = type) do
    expected_type_for_tuple_arg(name, tuple, Type.expected_value(type))
  end

  defp expected_type_for_arg_expr(_name, _arg, _expected_type), do: nil

  defp expected_type_for_tuple_arg(name, tuple, %Type{kind: :tuple, meta: %{elements: types}}) do
    case Pattern.tuple_elements(tuple) do
      elements when is_list(elements) and length(elements) == length(types) ->
        elements
        |> Enum.zip(types)
        |> Enum.find_value(fn {element, type} ->
          expected_type_for_arg_expr(name, element, type)
        end)

      _not_tuple ->
        nil
    end
  end

  defp expected_type_for_tuple_arg(_name, _tuple, _type), do: nil

  defp receiver_type_for_as_ref_argument(%Type{kind: :impl_trait, meta: %{traits: traits}}) do
    traits
    |> Enum.find_value(fn
      %Type{meta: %{syn_name: "Into", args: [type]}} -> receiver_type_for_as_ref_argument(type)
      _trait -> nil
    end)
  end

  defp receiver_type_for_as_ref_argument(%Type{
         kind: :option,
         meta: %{inner: %Type{kind: :ref, meta: %{inner: inner}}}
       }) do
    %Type{
      kind: :option,
      rust: "Option<#{inner.rust}>",
      ast: %AST.TypeOption{inner: inner.ast},
      meta: %{inner: inner}
    }
  end

  defp receiver_type_for_as_ref_argument(_type), do: nil

  defp receiver_type_for_as_slice_argument(%Type{kind: :impl_trait, meta: %{traits: traits}}) do
    traits
    |> Enum.find_value(fn
      %Type{meta: %{syn_name: "Into", args: [type]}} -> receiver_type_for_as_slice_argument(type)
      _trait -> nil
    end)
  end

  defp receiver_type_for_as_slice_argument(%Type{kind: :option, meta: %{inner: inner}}),
    do: receiver_type_for_as_slice_argument(inner)

  defp receiver_type_for_as_slice_argument(%Type{
         kind: kind,
         meta: %{inner: %Type{kind: :slice, meta: %{inner: inner}}}
       })
       when kind in [:ref, :mut_ref],
       do: vec_type(inner)

  defp receiver_type_for_as_slice_argument(%Type{kind: :slice, meta: %{inner: inner}}),
    do: vec_type(inner)

  defp receiver_type_for_as_slice_argument(_type), do: nil

  defp vec_type(%Type{} = inner) do
    %Type{
      kind: :vec,
      rust: "Vec<#{inner.rust}>",
      ast: %AST.TypeVec{inner: inner.ast},
      meta: %{inner: inner}
    }
  end

  defp expected_return_type_for_var(name, expression, %Type{} = return_type) do
    expression
    |> return_expressions()
    |> Enum.find_value(&expected_type_for_return_expr(name, &1, return_type))
  end

  defp expected_return_type_for_var(_name, _expression, _return_type), do: nil

  defp return_expressions({:if, _, [_condition, branches]}) when is_list(branches) do
    branches
    |> Keyword.take([:do, :else])
    |> Keyword.values()
    |> Enum.flat_map(&return_expressions/1)
  end

  defp return_expressions({:case, _, [_expression, [do: clauses]]}) do
    Enum.flat_map(clauses, fn {:->, _, [_patterns, body]} -> return_expressions(body) end)
  end

  defp return_expressions({:__block__, _, expressions}),
    do: return_expressions(List.last(expressions))

  defp return_expressions({:return!, _, [expression]}), do: [expression]
  defp return_expressions(expression), do: [expression]

  defp expected_type_for_return_expr(name, {:ok, value}, %Type{} = return_type) do
    case Type.inner(return_type) do
      %Type{} = inner -> expected_type_for_return_expr(name, value, inner)
      nil -> nil
    end
  end

  defp expected_type_for_return_expr(name, {:some, _, [value]}, %Type{kind: :option} = type) do
    case Type.inner(type) do
      %Type{} = inner -> expected_type_for_return_expr(name, value, inner)
      nil -> nil
    end
  end

  defp expected_type_for_return_expr(name, {var_name, _, context}, %Type{} = type)
       when name == var_name and is_atom(context),
       do: type

  defp expected_type_for_return_expr(name, tuple, %Type{kind: :tuple, meta: %{elements: types}}) do
    case Pattern.tuple_elements(tuple) do
      elements when is_list(elements) and length(elements) == length(types) ->
        elements
        |> Enum.zip(types)
        |> Enum.find_value(fn {element, type} ->
          expected_type_for_return_expr(name, element, type)
        end)

      _not_tuple ->
        nil
    end
  end

  defp expected_type_for_return_expr(_name, _expression, _type), do: nil

  defp expected_receiver_type_for_var(name, ast, callbacks, rhs_success_type) do
    {_ast, receiver_types} =
      Macro.prewalk(ast, [], &collect_downstream_receiver_type(&1, &2, name, callbacks))

    Enum.find(receiver_types, &match?(%Type{}, &1)) ||
      if(Enum.any?(receiver_types, &(&1 == :unknown_receiver)), do: rhs_success_type)
  end

  defp collect_downstream_receiver_type(
         {{:., _, [{var_name, _, context}, function]}, _meta, args} = ast,
         receiver_types,
         name,
         callbacks
       )
       when name == var_name and is_atom(context) and is_atom(function) and is_list(args) do
    receiver_type = callbacks.method_receiver_type.(function, length(args)) || :unknown_receiver
    {ast, [receiver_type | receiver_types]}
  end

  defp collect_downstream_receiver_type(ast, receiver_types, _name, _callbacks),
    do: {ast, receiver_types}

  defp downstream_call_arg_types(ast, vars, callbacks) do
    {_ast, calls} =
      Macro.prewalk(ast, [], &collect_downstream_call_arg_types(&1, &2, vars, callbacks))

    calls
  end

  defp collect_downstream_call_arg_types({name, _meta, args} = ast, calls, _vars, callbacks)
       when is_atom(name) and is_list(args) do
    {ast,
     maybe_add_downstream_call(calls, args, callbacks.local_argument_types.(name, length(args)))}
  end

  defp collect_downstream_call_arg_types(
         {{:., _, [{:__aliases__, _, parts}, function]}, _meta, args} = ast,
         calls,
         _vars,
         callbacks
       )
       when is_atom(function) and is_list(args) do
    {ast,
     maybe_add_downstream_call(
       calls,
       args,
       callbacks.path_argument_types.(parts, function, length(args))
     )}
  end

  defp collect_downstream_call_arg_types(
         {{:., _, [receiver, function]}, _meta, args} = ast,
         calls,
         vars,
         callbacks
       )
       when is_atom(function) and is_list(args) do
    target_type = infer_expr_type(receiver, vars)
    target = callbacks.target_type.(target_type)

    expected_types =
      method_expected_types(target_type, target, function, args, callbacks)

    {ast, maybe_add_downstream_call(calls, args, expected_types)}
  end

  defp collect_downstream_call_arg_types(ast, calls, _vars, _callbacks), do: {ast, calls}

  defp method_expected_types(%Type{} = receiver_type, _target, :push, [_arg], _callbacks) do
    receiver_type = Type.ref_inner(receiver_type) || receiver_type

    case Type.vec_inner(receiver_type) do
      %Type{} = inner -> [inner]
      nil -> nil
    end
  end

  defp method_expected_types(
         %Type{} = receiver_type,
         _target,
         :binary_search_by_key,
         [_key_arg, closure],
         _callbacks
       ) do
    with %Type{} = item_type <- slice_item_type(receiver_type),
         %Type{} = key_type <- closure_field_return_type(closure, item_type) do
      [ref_type(key_type), nil]
    else
      _no_key_type -> nil
    end
  end

  defp method_expected_types(_receiver_type, target, function, args, callbacks) do
    callbacks.method_argument_types.(target, function, length(args))
  end

  defp maybe_add_downstream_call(calls, args, [_ | _] = expected_types),
    do: [{args, expected_types} | calls]

  defp maybe_add_downstream_call(calls, _args, _expected_types), do: calls

  defp slice_item_type(%Type{kind: :slice, meta: %{inner: %Type{} = inner}}), do: inner

  defp slice_item_type(%Type{} = type) do
    type
    |> Type.ref_inner()
    |> Kernel.||(type)
    |> case do
      %Type{kind: :slice, meta: %{inner: %Type{} = inner}} -> inner
      %Type{ast: %AST.TypeSlice{inner: inner}} -> ast_type(inner)
      _other -> nil
    end
  end

  defp closure_field_return_type(
         {:fn, _meta, [{:->, _, [[{name, _, context}], body]}]},
         %Type{} = item_type
       )
       when is_atom(name) and is_atom(context) do
    closure_binding_field_type(body, name, item_type)
  end

  defp closure_field_return_type(_closure, _item_type), do: nil

  defp closure_binding_field_type(
         {{:., _, [{name, _, context}, field]}, _meta, []},
         name,
         item_type
       )
       when is_atom(name) and is_atom(context) and is_atom(field) do
    struct_field_type(item_type, field)
  end

  defp closure_binding_field_type(_body, _name, _item_type), do: nil

  defp struct_field_type(%Type{meta: %{fields: fields}}, field) when is_list(fields) do
    fields
    |> Enum.find_value(fn
      {^field, %Type{} = type, _presence} -> type
      {^field, %Type{} = type} -> type
      _other -> nil
    end)
  end

  defp struct_field_type(%Type{}, _field), do: nil

  defp ref_type(%Type{} = inner) do
    %Type{
      kind: :ref,
      rust: "&#{inner.rust}",
      ast: %AST.TypeRef{inner: inner.ast},
      meta: %{inner: inner}
    }
  end

  defp ast_type(ast),
    do: %Type{
      kind: :type,
      ast: ast,
      rust: ast |> RustQ.Rust.AST.Render.render_type() |> IO.iodata_to_binary()
    }

  defp infer_expr_type({name, _, context}, vars) when is_atom(name) and is_atom(context),
    do: Map.get(vars, name)

  defp infer_expr_type(_expression, _vars), do: nil
end
