defmodule RustQ.Meta.Lower do
  @moduledoc false

  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  @spec function_ast(Macro.t(), Type.t(), map()) :: [struct()]
  def function_ast(body_ast, return_type, vars \\ %{}) do
    body =
      body_ast
      |> block_expressions()
      |> lower_block(return_type, vars)

    infer_mutability(body)
  end

  @spec function_body(Macro.t(), Type.t(), map()) :: String.t()
  def function_body(body_ast, return_type, vars \\ %{}) do
    body_ast
    |> function_ast(return_type, vars)
    |> Enum.map(&AST.render_stmt/1)
    |> Enum.join("\n")
  end

  defp lower_block(expressions, return_type, vars) do
    {statements, final} = split_final(expressions)
    Enum.map(statements, &lower_statement(&1, vars)) ++ [lower_return(final, return_type, vars)]
  end

  defp split_final([]), do: {[], :ok}
  defp split_final(expressions), do: {Enum.drop(expressions, -1), List.last(expressions)}

  defp block_expressions({:__block__, _, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]

  defp lower_statement({:=, _, [pattern, expression]}, _vars) do
    %AST.Let{pattern: lower_binding_pattern(pattern), expr: lower_expr(expression)}
  end

  defp lower_statement({:case, _, [expression, [do: clauses]]}, vars) do
    %AST.ExprStmt{expr: lower_case(expression, clauses, :statement, vars)}
  end

  defp lower_statement({:if, _, [condition, branches]}, vars) do
    %AST.ExprStmt{expr: lower_if(condition, branches, :statement, vars)}
  end

  defp lower_statement(:ok, _vars), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(nil, _vars), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(expression, _vars), do: %AST.ExprStmt{expr: lower_expr(expression)}

  defp lower_return({:case, _, [expression, [do: clauses]]}, return_type, vars) do
    %AST.Return{expr: lower_case(expression, clauses, {:return, return_type}, vars)}
  end

  defp lower_return({:if, _, [condition, branches]}, return_type, vars) do
    %AST.Return{expr: lower_if(condition, branches, {:return, return_type}, vars)}
  end

  defp lower_return(:ok, %Type{kind: :nif_result, rust: "NifResult<()>"}, _vars),
    do: %AST.Return{expr: %AST.Ok{}}

  defp lower_return(:ok, _return_type, _vars), do: %AST.Return{expr: %AST.Tuple{values: []}}
  defp lower_return(nil, %Type{kind: :option}, _vars), do: %AST.Return{expr: %AST.None{}}

  defp lower_return({:ok, value}, %Type{kind: kind}, _vars) when kind in [:result, :nif_result] do
    %AST.Return{expr: %AST.Ok{expr: lower_expr(value)}}
  end

  defp lower_return({:error, value}, %Type{kind: :nif_result}, _vars) do
    %AST.Return{expr: %AST.Err{expr: lower_nif_error(value)}}
  end

  defp lower_return({:error, value}, %Type{kind: :result}, _vars) do
    %AST.Return{expr: %AST.Err{expr: lower_expr(value)}}
  end

  defp lower_return(expression, %Type{kind: :option}, _vars) do
    %AST.Return{expr: %AST.Some{expr: lower_expr(expression)}}
  end

  defp lower_return(expression, _return_type, _vars),
    do: %AST.Return{expr: lower_expr(expression)}

  defp lower_case(expression, clauses, context, vars) do
    case_type = infer_expr_type(expression, vars)

    arms =
      Enum.map(clauses, fn {:->, _, [[pattern], body]} ->
        %AST.Arm{
          pattern: lower_match_pattern(pattern, case_type),
          body: lower_clause_body(body, context, vars)
        }
      end)

    %AST.Match{expr: lower_expr(expression), arms: arms}
  end

  defp lower_if(condition, branches, context, vars) do
    then_body = Keyword.fetch!(branches, :do)
    else_body = Keyword.get(branches, :else, nil)

    %AST.If{
      condition: lower_expr(condition),
      then: lower_clause_body(then_body, context, vars),
      else: lower_clause_body(else_body, context, vars)
    }
  end

  defp lower_clause_body(body, :statement, vars) do
    body
    |> block_expressions()
    |> Enum.map(&lower_statement(&1, vars))
    |> reject_unit_statements()
  end

  defp lower_clause_body(body, {:return, return_type}, vars) do
    body
    |> block_expressions()
    |> lower_block(return_type, vars)
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

  defp lower_match_pattern(nil, %Type{kind: :option}), do: %AST.PatNone{}
  defp lower_match_pattern(nil, _case_type), do: %AST.PatNone{}
  defp lower_match_pattern({:_, _, _}, _case_type), do: %AST.PatWildcard{}

  defp lower_match_pattern({:ok, pattern}, _case_type),
    do: %AST.PatOk{pattern: lower_match_pattern(pattern, nil)}

  defp lower_match_pattern({:error, pattern}, _case_type),
    do: %AST.PatErr{pattern: lower_match_pattern(pattern, nil)}

  defp lower_match_pattern({:%, _, [{:__aliases__, _, [module]}, {:%{}, _, fields}]}, %Type{
         kind: :tuple_enum,
         rust: rust_name
       }) do
    %AST.PatPathTuple{
      path: %AST.Path{parts: [rust_name, module]},
      patterns: [
        %AST.PatStruct{
          path: %AST.Path{parts: [module]},
          fields:
            Enum.map(fields, fn {name, pattern} -> {name, lower_match_pattern(pattern, nil)} end)
        }
      ]
    }
  end

  defp lower_match_pattern({name, _, context}, %Type{kind: :option})
       when is_atom(name) and is_atom(context),
       do: %AST.PatSome{pattern: %AST.PatVar{name: name}}

  defp lower_match_pattern({name, _, context}, _case_type)
       when is_atom(name) and is_atom(context),
       do: %AST.PatVar{name: name}

  defp lower_match_pattern(atom, %Type{kind: kind}) when is_atom(atom) and kind in [:atom, :enum],
    do: %AST.PatAtomGuard{name: atom}

  defp lower_match_pattern(atom, _case_type) when is_atom(atom), do: %AST.PatAtomGuard{name: atom}

  defp lower_match_pattern({:{}, _, values}, _case_type) do
    %AST.PatTuple{patterns: Enum.map(values, &lower_tuple_pattern/1)}
  end

  defp lower_match_pattern(other, _case_type) do
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

  defp lower_expr({:token_macro, _, [path, tokens]}),
    do: %AST.TokenMacro{path: lower_token_macro_path(path), tokens: tokens}

  defp lower_expr({:quote_expr!, _, [tokens]}),
    do: %AST.PathCall{
      path: %AST.Path{parts: [:super, :parse_expr_tokens]},
      args: [quote_tokens(tokens)]
    }

  defp lower_expr({:quote_pat!, _, [tokens]}),
    do: %AST.PathCall{path: %AST.Path{parts: [:super, :parse_pat]}, args: [quote_tokens(tokens)]}

  defp lower_expr({:quote_stmt!, _, [tokens]}),
    do: %AST.PathCall{path: %AST.Path{parts: [:super, :parse_stmt]}, args: [quote_tokens(tokens)]}

  defp lower_expr({:badarg, _, []}), do: %AST.Path{parts: [:rustler, :Error, :BadArg]}

  defp lower_expr({:==, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :eq, right: lower_expr(right)}

  defp lower_expr({:and, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :and, right: lower_expr(right)}

  defp lower_expr({:or, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :or, right: lower_expr(right)}

  defp lower_expr({:if, _, [condition, branches]}),
    do: lower_if(condition, branches, :statement, %{})

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

    cond do
      super_alias_ast?(receiver) ->
        %AST.PathCall{path: %AST.Path{parts: [:super, function]}, args: args}

      rust_constructor_alias?(receiver) ->
        %AST.PathCall{
          path: %AST.Path{parts: alias_parts(receiver) ++ [rust_variant(function)]},
          args: args
        }

      alias_ast?(receiver) ->
        %AST.PathCall{path: %AST.Path{parts: alias_parts(receiver) ++ [function]}, args: args}

      true ->
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

  defp quote_tokens(tokens) when is_binary(tokens),
    do: %AST.TokenMacro{path: %AST.Path{parts: [:quote]}, tokens: tokens}

  defp quote_tokens(other) do
    raise ArgumentError, "unsupported quote tokens: #{Macro.to_string(other)}"
  end

  defp lower_token_macro_path(atom) when is_atom(atom), do: %AST.Path{parts: [atom]}
  defp lower_token_macro_path({:__aliases__, _, parts}), do: %AST.Path{parts: parts}

  defp lower_token_macro_path(other) do
    raise ArgumentError, "unsupported token_macro path: #{Macro.to_string(other)}"
  end

  defp infer_expr_type({name, _, context}, vars) when is_atom(name) and is_atom(context),
    do: Map.get(vars, name)

  defp infer_expr_type(_expression, _vars), do: nil

  defp infer_mutability(body) do
    mutable_vars = body |> collect_mut_refs() |> MapSet.new()
    Enum.map(body, &mark_mutable_lets(&1, mutable_vars))
  end

  defp mark_mutable_lets(%AST.Let{pattern: %AST.PatVar{name: name}} = let, mutable_vars) do
    %{
      let
      | mutable: MapSet.member?(mutable_vars, name),
        expr: mark_mutable_expr(let.expr, mutable_vars)
    }
  end

  defp mark_mutable_lets(%AST.ExprStmt{} = stmt, mutable_vars),
    do: %{stmt | expr: mark_mutable_expr(stmt.expr, mutable_vars)}

  defp mark_mutable_lets(%AST.Return{} = stmt, mutable_vars),
    do: %{stmt | expr: mark_mutable_expr(stmt.expr, mutable_vars)}

  defp mark_mutable_expr(%AST.Match{} = match, mutable_vars) do
    arms =
      Enum.map(match.arms, fn %AST.Arm{} = arm ->
        %{arm | body: Enum.map(arm.body, &mark_mutable_lets(&1, mutable_vars))}
      end)

    %{match | expr: mark_mutable_expr(match.expr, mutable_vars), arms: arms}
  end

  defp mark_mutable_expr(expr, mutable_vars), do: mark_mutable_expr_fallback(expr, mutable_vars)

  defp mark_mutable_expr_fallback(%AST.PathCall{} = expr, mutable_vars),
    do: %{expr | args: Enum.map(expr.args, &mark_mutable_expr(&1, mutable_vars))}

  defp mark_mutable_expr_fallback(%AST.MethodCall{} = expr, mutable_vars) do
    %{
      expr
      | receiver: mark_mutable_expr(expr.receiver, mutable_vars),
        args: Enum.map(expr.args, &mark_mutable_expr(&1, mutable_vars))
    }
  end

  defp mark_mutable_expr_fallback(%AST.LocalCall{} = expr, mutable_vars),
    do: %{expr | args: Enum.map(expr.args, &mark_mutable_expr(&1, mutable_vars))}

  defp mark_mutable_expr_fallback(%AST.Field{} = expr, mutable_vars),
    do: %{expr | receiver: mark_mutable_expr(expr.receiver, mutable_vars)}

  defp mark_mutable_expr_fallback(%AST.Ref{} = expr, mutable_vars),
    do: %{expr | expr: mark_mutable_expr(expr.expr, mutable_vars)}

  defp mark_mutable_expr_fallback(%AST.Try{} = expr, mutable_vars),
    do: %{expr | expr: mark_mutable_expr(expr.expr, mutable_vars)}

  defp mark_mutable_expr_fallback(%AST.Tuple{} = expr, mutable_vars),
    do: %{expr | values: Enum.map(expr.values, &mark_mutable_expr(&1, mutable_vars))}

  defp mark_mutable_expr_fallback(%AST.Some{} = expr, mutable_vars),
    do: %{expr | expr: mark_mutable_expr(expr.expr, mutable_vars)}

  defp mark_mutable_expr_fallback(%AST.Ok{expr: nil} = expr, _mutable_vars), do: expr

  defp mark_mutable_expr_fallback(%AST.Ok{} = expr, mutable_vars),
    do: %{expr | expr: mark_mutable_expr(expr.expr, mutable_vars)}

  defp mark_mutable_expr_fallback(%AST.Err{} = expr, mutable_vars),
    do: %{expr | expr: mark_mutable_expr(expr.expr, mutable_vars)}

  defp mark_mutable_expr_fallback(expr, _mutable_vars), do: expr

  defp collect_mut_refs(term), do: do_collect_mut_refs(term, [])

  defp do_collect_mut_refs(%AST.Ref{mutable: true, expr: %AST.Var{name: name}} = ref, acc) do
    do_collect_mut_refs(ref.expr, [name | acc])
  end

  defp do_collect_mut_refs(%{__struct__: _struct} = term, acc) do
    term
    |> Map.from_struct()
    |> Map.values()
    |> Enum.reduce(acc, &do_collect_mut_refs/2)
  end

  defp do_collect_mut_refs(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &do_collect_mut_refs/2)

  defp do_collect_mut_refs(_other, acc), do: acc

  defp alias_ast?({:__aliases__, _, _parts}), do: true
  defp alias_ast?(_other), do: false

  defp super_alias_ast?({:__aliases__, _, [:Super]}), do: true
  defp super_alias_ast?(_other), do: false

  defp rust_constructor_alias?({:__aliases__, _, [module]}) when module in [:Stmt], do: true
  defp rust_constructor_alias?(_other), do: false

  defp rust_variant(name), do: name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()

  defp alias_parts({:__aliases__, _, parts}), do: parts
end
