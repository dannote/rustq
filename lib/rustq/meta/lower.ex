defmodule RustQ.Meta.Lower do
  @moduledoc false

  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  @spec function_ast(Macro.t(), Type.t()) :: [struct()]
  def function_ast(body_ast, return_type) do
    body_ast
    |> block_expressions()
    |> lower_block(return_type)
  end

  @spec function_body(Macro.t(), Type.t()) :: String.t()
  def function_body(body_ast, return_type) do
    body_ast
    |> function_ast(return_type)
    |> Enum.map(&AST.render_stmt/1)
    |> Enum.join("\n")
  end

  defp lower_block(expressions, return_type) do
    {statements, final} = split_final(expressions)
    Enum.map(statements, &lower_statement/1) ++ [lower_return(final, return_type)]
  end

  defp split_final([]), do: {[], :ok}
  defp split_final(expressions), do: {Enum.drop(expressions, -1), List.last(expressions)}

  defp block_expressions({:__block__, _, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]

  defp lower_statement({:=, _, [pattern, expression]}) do
    %AST.Let{pattern: lower_binding_pattern(pattern), expr: lower_expr(expression)}
  end

  defp lower_statement({:case, _, [expression, [do: clauses]]}) do
    %AST.ExprStmt{expr: lower_case(expression, clauses, :statement)}
  end

  defp lower_statement(:ok), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(nil), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(expression), do: %AST.ExprStmt{expr: lower_expr(expression)}

  defp lower_return({:case, _, [expression, [do: clauses]]}, return_type) do
    %AST.Return{expr: lower_case(expression, clauses, {:return, return_type})}
  end

  defp lower_return(:ok, %Type{kind: :nif_result, rust: "NifResult<()>"}),
    do: %AST.Return{expr: %AST.Ok{}}

  defp lower_return(:ok, _return_type), do: %AST.Return{expr: %AST.Tuple{values: []}}
  defp lower_return(nil, %Type{kind: :option}), do: %AST.Return{expr: %AST.None{}}

  defp lower_return({:ok, value}, %Type{kind: kind}) when kind in [:result, :nif_result] do
    %AST.Return{expr: %AST.Ok{expr: lower_expr(value)}}
  end

  defp lower_return({:error, value}, %Type{kind: :nif_result}) do
    %AST.Return{expr: %AST.Err{expr: lower_nif_error(value)}}
  end

  defp lower_return({:error, value}, %Type{kind: :result}) do
    %AST.Return{expr: %AST.Err{expr: lower_expr(value)}}
  end

  defp lower_return(expression, %Type{kind: :option}) do
    %AST.Return{expr: %AST.Some{expr: lower_expr(expression)}}
  end

  defp lower_return(expression, _return_type), do: %AST.Return{expr: lower_expr(expression)}

  defp lower_case(expression, clauses, context) do
    option_case? = Enum.any?(clauses, fn {:->, _, [[pattern], _body]} -> pattern == nil end)

    arms =
      Enum.map(clauses, fn {:->, _, [[pattern], body]} ->
        %AST.Arm{
          pattern: lower_match_pattern(pattern, option_case?),
          body: lower_clause_body(body, context)
        }
      end)

    %AST.Match{expr: lower_expr(expression), arms: arms}
  end

  defp lower_clause_body(body, :statement) do
    body
    |> block_expressions()
    |> Enum.map(&lower_statement/1)
    |> reject_unit_statements()
  end

  defp lower_clause_body(body, {:return, return_type}) do
    body
    |> block_expressions()
    |> lower_block(return_type)
  end

  defp reject_unit_statements(statements) do
    Enum.reject(statements, fn
      %AST.ExprStmt{expr: %AST.Tuple{values: []}} -> true
      _other -> false
    end)
  end

  defp lower_binding_pattern({name, _, context}) when is_atom(name) and is_atom(context),
    do: %AST.PatVar{name: name}

  defp lower_binding_pattern(other) do
    raise ArgumentError, "unsupported defrust binding pattern: #{Macro.to_string(other)}"
  end

  defp lower_match_pattern(nil, _option_case?), do: %AST.PatNone{}
  defp lower_match_pattern({:_, _, _}, _option_case?), do: %AST.PatWildcard{}

  defp lower_match_pattern({name, _, context}, true) when is_atom(name) and is_atom(context),
    do: %AST.PatSome{pattern: %AST.PatVar{name: name}}

  defp lower_match_pattern({name, _, context}, false) when is_atom(name) and is_atom(context),
    do: %AST.PatVar{name: name}

  defp lower_match_pattern(atom, _option_case?) when is_atom(atom),
    do: %AST.PatAtomGuard{name: atom}

  defp lower_match_pattern({:{}, _, values}, _option_case?) do
    %AST.PatTuple{patterns: Enum.map(values, &lower_tuple_pattern/1)}
  end

  defp lower_match_pattern(other, _option_case?) do
    raise ArgumentError, "unsupported defrust match pattern: #{Macro.to_string(other)}"
  end

  defp lower_tuple_pattern({name, _, context}) when is_atom(name) and is_atom(context),
    do: %AST.PatVar{name: name}

  defp lower_tuple_pattern({:_, _, _}), do: %AST.PatWildcard{}
  defp lower_tuple_pattern(nil), do: %AST.PatNone{}
  defp lower_tuple_pattern(atom) when is_atom(atom), do: %AST.PatAtomGuard{name: atom}

  defp lower_expr({:unwrap!, _, [expression]}), do: %AST.Try{expr: lower_expr(expression)}
  defp lower_expr({:ref, _, [expression]}), do: %AST.Ref{expr: lower_expr(expression)}

  defp lower_expr({:mut_ref, _, [expression]}),
    do: %AST.Ref{expr: lower_expr(expression), mutable: true}

  defp lower_expr({:some, _, [expression]}), do: %AST.Some{expr: lower_expr(expression)}
  defp lower_expr({:none, _, []}), do: %AST.None{}
  defp lower_expr({:ok, _, []}), do: %AST.Ok{}
  defp lower_expr({:ok, _, [expression]}), do: %AST.Ok{expr: lower_expr(expression)}
  defp lower_expr({:err, _, [expression]}), do: %AST.Err{expr: lower_expr(expression)}

  defp lower_expr({{:., _meta, [receiver, field_or_function]}, call_meta, []}) do
    cond do
      Keyword.get(call_meta, :no_parens) ->
        %AST.Field{receiver: lower_expr(receiver), field: field_or_function}

      alias_ast?(receiver) ->
        %AST.Path{parts: alias_parts(receiver) ++ [field_or_function]}

      true ->
        %AST.MethodCall{receiver: lower_expr(receiver), method: field_or_function}
    end
  end

  defp lower_expr({{:., _meta, [receiver, function]}, _, args}) do
    args = Enum.map(args, &lower_expr/1)

    if alias_ast?(receiver) do
      %AST.PathCall{path: %AST.Path{parts: alias_parts(receiver) ++ [function]}, args: args}
    else
      %AST.MethodCall{receiver: lower_expr(receiver), method: function, args: args}
    end
  end

  defp lower_expr({:__aliases__, _, parts}), do: %AST.Path{parts: parts}

  defp lower_expr({name, _, args}) when is_atom(name) and is_list(args) do
    %AST.LocalCall{name: name, args: Enum.map(args, &lower_expr/1)}
  end

  defp lower_expr({name, _, context}) when is_atom(name) and is_atom(context),
    do: %AST.Var{name: name}

  defp lower_expr({:{}, _, values}), do: %AST.Tuple{values: Enum.map(values, &lower_expr/1)}
  defp lower_expr(value) when is_binary(value), do: %AST.Literal{value: value}
  defp lower_expr(value) when is_integer(value) or is_float(value), do: %AST.Literal{value: value}
  defp lower_expr(true), do: %AST.Literal{value: true}
  defp lower_expr(false), do: %AST.Literal{value: false}
  defp lower_expr(nil), do: %AST.None{}
  defp lower_expr(atom) when is_atom(atom), do: %AST.AtomValue{name: atom}

  defp lower_expr(other) do
    raise ArgumentError, "unsupported defrust expression: #{Macro.to_string(other)}"
  end

  defp lower_nif_error(atom) when is_atom(atom), do: %AST.NifRaiseAtom{name: atom}
  defp lower_nif_error(other), do: lower_expr(other)

  defp alias_ast?({:__aliases__, _, _parts}), do: true
  defp alias_ast?(_other), do: false

  defp alias_parts({:__aliases__, _, parts}), do: parts
end
