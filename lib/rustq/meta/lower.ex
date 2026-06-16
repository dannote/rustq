defmodule RustQ.Meta.Lower do
  @moduledoc false

  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  defmodule Context do
    @moduledoc false
    defstruct [:return_type, vars: %{}, position: :return]
  end

  @spec function_ast(Macro.t(), Type.t(), map()) :: [struct()]
  def function_ast(body_ast, return_type, vars \\ %{}) do
    context = %Context{return_type: return_type, vars: vars}

    body =
      body_ast
      |> block_expressions()
      |> lower_block(context)

    infer_mutability(body)
  end

  @spec function_body(Macro.t(), Type.t(), map()) :: String.t()
  def function_body(body_ast, return_type, vars \\ %{}) do
    body_ast
    |> function_ast(return_type, vars)
    |> Enum.map(&AST.render_stmt/1)
    |> Enum.join("\n")
  end

  defp lower_block(expressions, %Context{} = context) do
    {statements, final} = split_final(expressions)
    statement_context = %{context | position: :statement}
    return_context = %{context | position: :return}

    Enum.map(statements, &lower_statement(&1, statement_context)) ++
      [lower_return(final, return_context)]
  end

  defp split_final([]), do: {[], :ok}
  defp split_final(expressions), do: {Enum.drop(expressions, -1), List.last(expressions)}

  defp block_expressions({:__block__, _, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]

  defp lower_statement({:=, _, [pattern, expression]}, %Context{}) do
    %AST.Let{pattern: lower_binding_pattern(pattern), expr: lower_expr(expression)}
  end

  defp lower_statement({:case, _, [expression, [do: clauses]]}, %Context{} = context) do
    %AST.ExprStmt{expr: lower_case(expression, clauses, context)}
  end

  defp lower_statement({:if, _, [condition, branches]}, %Context{} = context) do
    %AST.ExprStmt{expr: lower_if(condition, branches, context)}
  end

  defp lower_statement(:ok, %Context{}), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(nil, %Context{}), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(expression, %Context{}), do: %AST.ExprStmt{expr: lower_expr(expression)}

  defp lower_return({:case, _, [expression, [do: clauses]]}, %Context{} = context) do
    %AST.Return{expr: lower_case(expression, clauses, context)}
  end

  defp lower_return({:if, _, [condition, branches]}, %Context{} = context) do
    %AST.Return{expr: lower_if(condition, branches, context)}
  end

  defp lower_return(expression, %Context{return_type: return_type}),
    do: %AST.Return{expr: lower_return_expr(expression, return_type)}

  defp lower_return_expr(:ok, %Type{kind: :nif_result, rust: "NifResult<()>"}), do: %AST.Ok{}
  defp lower_return_expr(:ok, _return_type), do: %AST.Tuple{values: []}
  defp lower_return_expr(nil, %Type{kind: :option}), do: %AST.None{}

  defp lower_return_expr({:ok, value}, %Type{kind: kind}) when kind in [:result, :nif_result],
    do: %AST.Ok{expr: lower_expr(value)}

  defp lower_return_expr({:error, value}, %Type{kind: :nif_result}),
    do: %AST.Err{expr: lower_nif_error(value)}

  defp lower_return_expr({:error, value}, %Type{kind: :result}),
    do: %AST.Err{expr: lower_expr(value)}

  defp lower_return_expr(expression, %Type{kind: :option}),
    do: %AST.Some{expr: lower_expr(expression)}

  defp lower_return_expr(expression, _return_type), do: lower_expr(expression)

  defp lower_case(expression, clauses, %Context{} = context) do
    case_type =
      infer_expr_type(expression, context.vars) || infer_case_type_from_patterns(clauses)

    arms =
      Enum.map(clauses, fn {:->, _, [[pattern], body]} ->
        %AST.Arm{
          pattern: lower_match_pattern(pattern, case_type),
          body: lower_clause_body(body, context)
        }
      end)

    %AST.Match{expr: lower_expr(expression), arms: arms}
  end

  defp lower_if(condition, branches, %Context{} = context) do
    then_body = Keyword.fetch!(branches, :do)
    else_body = Keyword.get(branches, :else, nil)

    %AST.If{
      condition: lower_expr(condition),
      then: lower_clause_body(then_body, context),
      else: lower_clause_body(else_body, context)
    }
  end

  defp lower_clause_body(body, %Context{position: :statement} = context) do
    body
    |> block_expressions()
    |> Enum.map(&lower_statement(&1, context))
    |> reject_unit_statements()
  end

  defp lower_clause_body(body, %Context{position: :return} = context) do
    body
    |> block_expressions()
    |> lower_block(context)
  end

  defp lower_clause_body(body, %Context{position: :expr} = context) do
    body
    |> block_expressions()
    |> lower_block(%{context | return_type: nil})
  end

  defp infer_case_type_from_patterns(clauses) do
    if Enum.any?(clauses, fn {:->, _, [[pattern], _body]} -> pattern == nil end) do
      %Type{kind: :option}
    end
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

  defp lower_match_pattern(value, _case_type) when is_binary(value),
    do: %AST.PatLiteral{value: value}

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

  defp lower_expr({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [collection, mapper]}),
    do: lower_enum_map(collection, mapper)

  defp lower_expr({:expr!, _, [expression]}), do: semantic_expr(expression)
  defp lower_expr({:pat!, _, [pattern]}), do: semantic_pat(pattern)
  defp lower_expr({:stmt!, _, [expression]}), do: semantic_stmt(expression)

  defp lower_expr({:raw_expr!, _, [tokens]}), do: parse_syn(:Expr, tokens)
  defp lower_expr({:raw_pat!, _, [tokens]}), do: parse_syn(:Pat, tokens)
  defp lower_expr({:raw_stmt!, _, [tokens]}), do: parse_syn(:Stmt, tokens)
  defp lower_expr({:raw_arm!, _, [tokens]}), do: parse_syn(:Arm, tokens)

  defp lower_expr({:arm!, _, [pattern, block]}), do: semantic_arm(pattern, block)

  defp lower_expr({:badarg, _, []}), do: %AST.Path{parts: [:rustler, :Error, :BadArg]}

  defp lower_expr({:==, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :eq, right: lower_expr(right)}

  defp lower_expr({:and, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :and, right: lower_expr(right)}

  defp lower_expr({:or, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :or, right: lower_expr(right)}

  defp lower_expr({:if, _, [condition, branches]}),
    do: lower_if(condition, branches, %Context{position: :expr})

  defp lower_expr({:case, _, [expression, [do: clauses]]}),
    do: lower_case(expression, clauses, %Context{position: :expr})

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

  defp lower_expr(values) when is_list(values),
    do: %AST.VecLiteral{values: Enum.map(values, &lower_expr/1)}

  defp lower_expr(value) when is_binary(value), do: %AST.Literal{value: value}
  defp lower_expr(value) when is_integer(value) or is_float(value), do: %AST.Literal{value: value}
  defp lower_expr(true), do: %AST.Literal{value: true}
  defp lower_expr(false), do: %AST.Literal{value: false}
  defp lower_expr(nil), do: %AST.None{}
  defp lower_expr(atom) when is_atom(atom), do: %AST.AtomValue{name: atom}

  defp lower_expr(other) do
    raise ArgumentError, "unsupported defrust expression: #{Macro.to_string(other)}"
  end

  defp lower_enum_map(collection, {:fn, _, [{:->, _, [[arg], body]}]}) do
    collection
    |> lower_expr()
    |> method_chain(:into_iter)
    |> method_chain(:map, [lower_closure(arg, body)])
    |> method_chain(:collect)
  end

  defp lower_enum_map(_collection, other) do
    raise ArgumentError, "unsupported Enum.map mapper in defrust: #{Macro.to_string(other)}"
  end

  defp lower_closure({name, _, context}, body) when is_atom(name) and is_atom(context),
    do: %AST.Closure{args: [name], body: lower_expr(closure_body_expr(body))}

  defp lower_closure(other, _body) do
    raise ArgumentError,
          "unsupported Enum.map closure argument in defrust: #{Macro.to_string(other)}"
  end

  defp closure_body_expr([expression]), do: expression
  defp closure_body_expr(expression), do: expression

  defp method_chain(receiver, method, args \\ []),
    do: %AST.MethodCall{receiver: receiver, method: method, args: args}

  defp lower_nif_error(atom) when is_atom(atom), do: %AST.NifRaiseAtom{name: atom}
  defp lower_nif_error(other), do: lower_expr(other)

  defp semantic_expr(:ok), do: raw_expr("Ok(())")
  defp semantic_expr({:ok, value}), do: raw_expr("Ok(#{semantic_interpolation(value)})")
  defp semantic_expr({:error, value}), do: raw_expr("Err(#{semantic_interpolation(value)})")
  defp semantic_expr({:{}, _, [:ok, value]}), do: raw_expr("Ok(#{semantic_interpolation(value)})")

  defp semantic_expr({:{}, _, [:error, value]}),
    do: raw_expr("Err(#{semantic_interpolation(value)})")

  defp semantic_expr({:some, _, [value]}), do: raw_expr("Some(#{semantic_interpolation(value)})")
  defp semantic_expr({:none, _, []}), do: raw_expr("None")
  defp semantic_expr({:err, _, [value]}), do: raw_expr("Err(#{semantic_interpolation(value)})")
  defp semantic_expr({:ref, _, [value]}), do: raw_expr("&#{semantic_interpolation(value)}")

  defp semantic_expr({:mut_ref, _, [value]}),
    do: raw_expr("&mut #{semantic_interpolation(value)}")

  defp semantic_expr({:unwrap!, _, [value]}), do: raw_expr("#{semantic_interpolation(value)}?")

  defp semantic_expr({:ident, _, [name]}), do: raw_expr(semantic_interpolation(name))

  defp semantic_expr({:field, _, [receiver, field]}),
    do: raw_expr("#{semantic_interpolation(receiver)}.#{semantic_ident(field)}")

  defp semantic_expr({:path_call, _, [path, args]}),
    do: raw_expr("#{semantic_interpolation(path)}(#{semantic_splice(args)})")

  defp semantic_expr({:method_call, _, [receiver, method, args]}),
    do:
      raw_expr(
        "#{semantic_interpolation(receiver)}.#{semantic_ident(method)}(#{semantic_splice(args)})"
      )

  defp semantic_expr({:struct_literal, _, [path, fields]}),
    do: raw_expr("#{semantic_interpolation(path)} { #{semantic_splice(fields)} }")

  defp semantic_expr({:tuple, _, [values]}), do: raw_expr("(#{semantic_splice(values)})")
  defp semantic_expr({:vec, _, [values]}), do: raw_expr("vec![#{semantic_splice(values)}]")

  defp semantic_expr({:closure, _, [args, body]}),
    do: raw_expr("|#{semantic_splice(args)}| #{semantic_interpolation(body)}")

  defp semantic_expr({:binary, _, [left, op, right]}),
    do:
      raw_expr(
        "#{semantic_interpolation(left)} #{semantic_binary_op(op)} #{semantic_interpolation(right)}"
      )

  defp semantic_expr({:match, _, [expr, arms]}),
    do: raw_expr("match #{semantic_interpolation(expr)} { #{semantic_concat(arms)} }")

  defp semantic_expr({:if_else, _, [condition, then_block, else_block]}),
    do:
      raw_expr(
        "if #{semantic_interpolation(condition)} #{semantic_interpolation(then_block)} else #{semantic_interpolation(else_block)}"
      )

  defp semantic_expr({:atom_value, _, [name]}), do: raw_expr("atoms::#{semantic_ident(name)}()")

  defp semantic_expr({:raise_atom, _, [name]}),
    do: raw_expr("rustler::Error::RaiseAtom(#{semantic_interpolation(name)})")

  defp semantic_expr(nil), do: raw_expr("None")

  defp semantic_expr(other), do: raw_expr(AST.render_expr(lower_expr(other)))

  defp semantic_pat({:ident, _, [name]}), do: raw_pat(semantic_interpolation(name))
  defp semantic_pat({:path, _, [path]}), do: raw_pat(semantic_interpolation(path))

  defp semantic_pat({:some, _, [pattern]}),
    do: raw_pat("Some(#{semantic_interpolation(pattern)})")

  defp semantic_pat({:ok, pattern}), do: raw_pat("Ok(#{semantic_interpolation(pattern)})")
  defp semantic_pat({:error, pattern}), do: raw_pat("Err(#{semantic_interpolation(pattern)})")

  defp semantic_pat({:{}, _, [:ok, pattern]}),
    do: raw_pat("Ok(#{semantic_interpolation(pattern)})")

  defp semantic_pat({:{}, _, [:error, pattern]}),
    do: raw_pat("Err(#{semantic_interpolation(pattern)})")

  defp semantic_pat({:tuple, _, [patterns]}), do: raw_pat("(#{semantic_splice(patterns)})")

  defp semantic_pat({:path_tuple, _, [path, patterns]}),
    do: raw_pat("#{semantic_interpolation(path)}(#{semantic_splice(patterns)})")

  defp semantic_pat({:struct, _, [path, fields]}),
    do: raw_pat("#{semantic_interpolation(path)} { #{semantic_splice(fields)} }")

  defp semantic_pat(nil), do: raw_pat("None")
  defp semantic_pat(:_), do: raw_pat("_")
  defp semantic_pat(other), do: raw_pat(semantic_interpolation(other))

  defp semantic_stmt(expression), do: raw_stmt("#{semantic_interpolation(expression)};")

  defp semantic_arm(pattern, block),
    do: parse_syn(:Arm, "#{semantic_interpolation(pattern)} => #{semantic_interpolation(block)},")

  defp semantic_interpolation({name, _, context}) when is_atom(name) and is_atom(context),
    do: "##{name}"

  defp semantic_interpolation(other), do: AST.render_expr(lower_expr(other))

  defp semantic_ident({name, _, context}) when is_atom(name) and is_atom(context), do: "##{name}"
  defp semantic_ident(name) when is_atom(name), do: Atom.to_string(name)

  defp semantic_splice({name, _, context}) when is_atom(name) and is_atom(context),
    do: "#(##{name}),*"

  defp semantic_concat({name, _, context}) when is_atom(name) and is_atom(context),
    do: "#(##{name})*"

  defp semantic_binary_op(:eq), do: "=="
  defp semantic_binary_op(:and), do: "&&"
  defp semantic_binary_op(:or), do: "||"

  defp raw_expr(tokens), do: parse_syn(:Expr, tokens)
  defp raw_pat(tokens), do: parse_syn(:Pat, tokens)
  defp raw_stmt(tokens), do: parse_syn(:Stmt, tokens)

  defp parse_syn(type, tokens) do
    %AST.PathCall{
      path: %AST.Path{parts: [:super, "parse_syn::<#{type}>"]},
      args: [quote_tokens(tokens)]
    }
  end

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

  defp mark_mutable_expr_fallback(%AST.VecLiteral{} = expr, mutable_vars),
    do: %{expr | values: Enum.map(expr.values, &mark_mutable_expr(&1, mutable_vars))}

  defp mark_mutable_expr_fallback(%AST.Closure{} = expr, mutable_vars),
    do: %{expr | body: mark_mutable_expr(expr.body, mutable_vars)}

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
