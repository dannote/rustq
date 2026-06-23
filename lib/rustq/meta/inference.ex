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
          required(:target_type) => (Type.t() | nil -> term())
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
         {:=, _, [{name, _, context}, _rhs]},
         expressions,
         index,
         vars,
         callbacks
       )
       when is_atom(name) and is_atom(context) do
    expressions
    |> Enum.drop(index + 1)
    |> Enum.find_value(&expected_type_for_var(name, &1, vars, callbacks))
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

  defp expected_type_for_var(name, ast, vars, callbacks) do
    ast
    |> downstream_call_arg_types(vars, callbacks)
    |> Enum.find_value(fn {args, expected_types} ->
      expected_type_for_arg(name, args, expected_types)
    end)
  end

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
       do: Type.expected_value(type)

  defp expected_type_for_arg_expr(
         name,
         {{:., _, [{var_name, _, context}, :as_ref]}, _meta, []},
         %Type{} = type
       )
       when name == var_name and is_atom(context),
       do: receiver_type_for_as_ref_argument(type)

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

    {ast,
     maybe_add_downstream_call(
       calls,
       args,
       callbacks.method_argument_types.(target, function, length(args))
     )}
  end

  defp collect_downstream_call_arg_types(ast, calls, _vars, _callbacks), do: {ast, calls}

  defp maybe_add_downstream_call(calls, args, [_ | _] = expected_types),
    do: [{args, expected_types} | calls]

  defp maybe_add_downstream_call(calls, _args, _expected_types), do: calls

  defp infer_expr_type({name, _, context}, vars) when is_atom(name) and is_atom(context),
    do: Map.get(vars, name)

  defp infer_expr_type(_expression, _vars), do: nil
end
