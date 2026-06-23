defmodule RustQ.Meta.Lower do
  @moduledoc """
  Lowers Rusty-Elixir quoted expressions into RustQ AST nodes.
  """

  alias RustQ.Binding.Index, as: BindingIndex
  alias RustQ.Diagnostic
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render

  defmodule Context do
    @moduledoc """
    Tracks return type, variables, aliases, callable metadata, and position while lowering a body.
    """
    defstruct [
      :return_type,
      vars: %{},
      position: :return,
      rust_modules: %{},
      callables: %BindingIndex{}
    ]
  end

  @spec quoted_body(Macro.t(), Type.t(), map(), keyword()) :: [struct()]
  def quoted_body(body_ast, return_type, vars \\ %{}, opts \\ []) do
    context = %Context{
      return_type: return_type,
      vars: vars,
      rust_modules: Keyword.get(opts, :rust_modules, %{}),
      callables: BindingIndex.new(Keyword.get(opts, :callables))
    }

    with_lowering_context(context, fn ->
      body_ast
      |> block_expressions()
      |> lower_block(context)
      |> infer_mutability()
    end)
  end

  @spec function_body(Macro.t(), Type.t(), map(), keyword()) :: String.t()
  def function_body(body_ast, return_type, vars \\ %{}, opts \\ []) do
    body_ast
    |> quoted_body(return_type, vars, opts)
    |> Enum.map_join("\n", &Render.render_stmt/1)
  end

  @doc """
  Looks up the known return type for a local or remote call AST.

  This is a lowering-time query over the callable metadata supplied through the
  `:callables` option. It is intentionally side-effect-free and does not alter
  lowering yet; type-driven propagation inference will use this lookup to decide
  when a call returning `Result`/`Option`/`NifResult` should lower with Rust `?`.
  """
  @spec callable_return_type(Macro.t(), keyword()) :: Type.t() | nil
  def callable_return_type(call_ast, opts \\ []) do
    callables =
      case Keyword.fetch(opts, :callables) do
        {:ok, callables} -> BindingIndex.new(callables)
        :error -> current_callables()
      end

    callable_return_type_from_index(call_ast, callables)
  end

  defp lower_block(expressions, %Context{} = context) do
    context = context_with_downstream_let_types(expressions, context)

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

  defp lower_statement({:assign!, _, [target, expression]}, %Context{} = context) do
    expected_type = infer_expr_type(target, context.vars)
    %AST.Assign{target: lower_expr(target), expr: lower_expr(expression, expected_type)}
  end

  defp lower_statement({:return!, _, [expression]}, %Context{return_type: return_type}) do
    %AST.EarlyReturn{expr: lower_return_expr(expression, return_type)}
  end

  defp lower_statement({:=, _, [pattern, expression]}, %Context{} = context) do
    expected_type = infer_let_expected_type(pattern, expression, context.vars)
    %AST.Let{pattern: lower_binding_pattern(pattern), expr: lower_expr(expression, expected_type)}
  end

  defp lower_statement({:case, _, [expression, [do: clauses]]}, %Context{} = context) do
    %AST.ExprStmt{expr: lower_case(expression, clauses, context)}
  end

  defp lower_statement({:if, _, [condition, branches]}, %Context{} = context) do
    %AST.ExprStmt{expr: lower_if(condition, branches, context)}
  end

  defp lower_statement(
         {:for, _, [{:<-, _, [pattern, expression]}, [do: body]]},
         %Context{} = context
       ) do
    %AST.For{
      pattern: lower_binding_pattern(pattern),
      expr: lower_expr(expression),
      body: lower_clause_body(body, context)
    }
  end

  defp lower_statement(:ok, %Context{}), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}
  defp lower_statement(nil, %Context{}), do: %AST.ExprStmt{expr: %AST.Tuple{values: []}}

  defp lower_statement(expression, %Context{return_type: return_type}) do
    %AST.ExprStmt{expr: lower_statement_expr(expression, return_type)}
  end

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

  defp lower_return_expr(expression, %Type{kind: :option} = return_type) do
    if infer_propagation?(expression, return_type) do
      %AST.Try{expr: lower_expr(expression)}
    else
      %AST.Some{expr: lower_expr(expression)}
    end
  end

  defp lower_return_expr(expression, %Type{} = return_type) do
    if infer_propagation?(expression, return_type) do
      %AST.Try{expr: lower_expr(expression)}
    else
      lower_expr(expression)
    end
  end

  defp lower_return_expr(expression, _return_type), do: lower_expr(expression)

  defp lower_expr(expression, %Type{} = expected_type) do
    if infer_propagation?(expression, expected_type) do
      %AST.Try{expr: lower_expr(expression)}
    else
      lower_expr(expression)
    end
  end

  defp lower_expr(expression, _expected_type), do: lower_expr(expression)

  defp lower_statement_expr(expression, %Type{} = return_type) do
    if infer_statement_propagation?(expression, return_type) do
      %AST.Try{expr: lower_expr(expression)}
    else
      lower_expr(expression)
    end
  end

  defp lower_statement_expr(expression, _return_type), do: lower_expr(expression)

  defp infer_statement_propagation?(expression, %Type{} = return_type) do
    same_wrapper_propagation?(expression, return_type)
  end

  defp lower_wrapper_arg_expr(expression) do
    if same_wrapper_propagation?(expression, current_return_type()) do
      %AST.Try{expr: lower_expr(expression)}
    else
      lower_expr(expression)
    end
  end

  defp same_wrapper_propagation?(expression, %Type{} = return_type) do
    case callable_return_type(expression) do
      %Type{kind: kind} = call_type ->
        Type.propagates?(call_type) and Type.propagates?(return_type) and kind == return_type.kind

      _unknown_or_plain ->
        false
    end
  end

  defp same_wrapper_propagation?(_expression, _return_type), do: false

  defp infer_propagation?(expression, %Type{} = expected_type) do
    case callable_return_type(expression) do
      %Type{} = call_type ->
        Type.propagates?(call_type) and
          call_type
          |> Type.inner()
          |> Type.compatible?(expected_type)

      _unknown_or_plain ->
        false
    end
  end

  defp lower_case(expression, clauses, %Context{} = context) do
    case_type =
      infer_expr_type(expression, context.vars) || infer_case_type_from_patterns(clauses)

    arms =
      Enum.map(clauses, fn {:->, _, [[pattern], body]} ->
        body = lower_clause_body(body, context)
        mutable_vars = body |> collect_mut_refs() |> MapSet.new()

        %AST.Arm{
          pattern:
            pattern |> lower_match_pattern(case_type) |> mark_mutable_pattern_vars(mutable_vars),
          body: body
        }
      end)

    %AST.Match{expr: lower_expr(expression), arms: arms}
  end

  defp lower_if(condition, branches, %Context{} = context) do
    then_body = Keyword.fetch!(branches, :do)
    else_body = Keyword.get(branches, :else)

    %AST.If{
      condition: lower_expr(condition),
      then: lower_clause_body(then_body, context),
      else: lower_clause_body(else_body, context)
    }
  end

  defp lower_clause_body(body, %Context{position: :statement} = context) do
    expressions = block_expressions(body)
    context = context_with_downstream_let_types(expressions, context)

    expressions
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
    if Enum.any?(clauses, fn {:->, _, [[pattern], _body]} -> option_pattern?(pattern) end) do
      %Type{kind: :option}
    end
  end

  defp option_pattern?(nil), do: true
  defp option_pattern?(:none), do: true
  defp option_pattern?({:some, _pattern}), do: true
  defp option_pattern?({:{}, _, [:some, _pattern]}), do: true
  defp option_pattern?(_pattern), do: false

  defp reject_unit_statements(statements) do
    Enum.reject(statements, fn
      %AST.ExprStmt{expr: %AST.Tuple{values: []}} -> true
      _other -> false
    end)
  end

  defp lower_binding_pattern({name, _, context}) when is_atom(name) and is_atom(context),
    do: %AST.PatVar{name: name}

  defp lower_binding_pattern({:{}, _, values}),
    do: %AST.PatTuple{patterns: Enum.map(values, &lower_binding_pattern/1)}

  defp lower_binding_pattern({left, right}),
    do: %AST.PatTuple{patterns: Enum.map([left, right], &lower_binding_pattern/1)}

  defp lower_binding_pattern(other) do
    Diagnostic.lower(
      :unsupported_binding_pattern,
      other,
      "unsupported defrust binding pattern",
      suggestion: "Use a variable or tuple pattern."
    )
  end

  defp lower_match_pattern(nil, %Type{kind: :option}), do: %AST.PatNone{}
  defp lower_match_pattern(:none, %Type{kind: :option}), do: %AST.PatNone{}
  defp lower_match_pattern(nil, _case_type), do: %AST.PatNone{}
  defp lower_match_pattern({:_, _, _}, _case_type), do: %AST.PatWildcard{}

  defp lower_match_pattern(value, _case_type) when is_binary(value) or is_integer(value),
    do: %AST.PatLiteral{value: value}

  defp lower_match_pattern({:ok, pattern}, _case_type),
    do: %AST.PatOk{pattern: lower_match_pattern(pattern, nil)}

  defp lower_match_pattern({:error, pattern}, _case_type),
    do: %AST.PatErr{pattern: lower_match_pattern(pattern, nil)}

  defp lower_match_pattern({:some, pattern}, %Type{kind: :option}),
    do: %AST.PatSome{pattern: lower_match_pattern(pattern, nil)}

  defp lower_match_pattern({:{}, _, [:some, pattern]}, %Type{kind: :option}),
    do: %AST.PatSome{pattern: lower_match_pattern(pattern, nil)}

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

  defp lower_match_pattern({left, right}, _case_type) do
    %AST.PatTuple{patterns: Enum.map([left, right], &lower_tuple_pattern/1)}
  end

  defp lower_match_pattern(other, _case_type) do
    Diagnostic.lower(
      :unsupported_match_pattern,
      other,
      "unsupported defrust match pattern",
      suggestion:
        "Use a variable, tuple, option/result pattern, atom, literal, or supported struct pattern."
    )
  end

  defp lower_tuple_pattern({name, _, context}) when is_atom(name) and is_atom(context),
    do: %AST.PatVar{name: name}

  defp lower_tuple_pattern({:{}, _, patterns}),
    do: %AST.PatTuple{patterns: Enum.map(patterns, &lower_tuple_pattern/1)}

  defp lower_tuple_pattern({:_, _, _}), do: %AST.PatWildcard{}

  defp lower_tuple_pattern(patterns) when is_tuple(patterns),
    do: %AST.PatTuple{patterns: patterns |> Tuple.to_list() |> Enum.map(&lower_tuple_pattern/1)}

  defp lower_tuple_pattern(nil), do: %AST.PatNone{}
  defp lower_tuple_pattern(atom) when is_atom(atom), do: %AST.PatAtomGuard{name: atom}

  defp mark_mutable_pattern_vars(%AST.PatVar{name: name} = pattern, mutable_vars) do
    if MapSet.member?(mutable_vars, name), do: %{pattern | mutable: true}, else: pattern
  end

  defp mark_mutable_pattern_vars(%AST.PatSome{pattern: pattern} = some, mutable_vars),
    do: %{some | pattern: mark_mutable_pattern_vars(pattern, mutable_vars)}

  defp mark_mutable_pattern_vars(%AST.PatOk{pattern: pattern} = ok, mutable_vars),
    do: %{ok | pattern: mark_mutable_pattern_vars(pattern, mutable_vars)}

  defp mark_mutable_pattern_vars(%AST.PatErr{pattern: pattern} = err, mutable_vars),
    do: %{err | pattern: mark_mutable_pattern_vars(pattern, mutable_vars)}

  defp mark_mutable_pattern_vars(%AST.PatTuple{patterns: patterns} = tuple, mutable_vars),
    do: %{tuple | patterns: Enum.map(patterns, &mark_mutable_pattern_vars(&1, mutable_vars))}

  defp mark_mutable_pattern_vars(%AST.PatPathTuple{patterns: patterns} = tuple, mutable_vars),
    do: %{tuple | patterns: Enum.map(patterns, &mark_mutable_pattern_vars(&1, mutable_vars))}

  defp mark_mutable_pattern_vars(%AST.PatStruct{fields: fields} = struct, mutable_vars) do
    fields =
      Enum.map(fields, fn {name, pattern} ->
        {name, mark_mutable_pattern_vars(pattern, mutable_vars)}
      end)

    %{struct | fields: fields}
  end

  defp mark_mutable_pattern_vars(pattern, _mutable_vars), do: pattern

  defp lower_expr({:unwrap!, _, [expression]}), do: %AST.Try{expr: lower_expr(expression)}

  defp lower_expr({:|>, _, [left, right]}), do: lower_pipe(left, right)

  defp lower_expr({:cast, _, [expression, type]}),
    do: %AST.Cast{expr: lower_expr(expression), type: RustQ.Spec.type(type).ast}

  defp lower_expr({:decode_as!, _, [expression, type_ast]}),
    do: %AST.Try{expr: decode_as_expr(expression, type_ast)}

  defp lower_expr({:decode_as, _, [expression, type_ast]}),
    do: decode_as_expr(expression, type_ast)

  defp lower_expr({:ref, _, [expression]}), do: %AST.Ref{expr: lower_expr(expression)}

  defp lower_expr({:mut_ref, _, [expression]}),
    do: %AST.Ref{expr: lower_expr(expression), mutable: true}

  defp lower_expr({:deref, _, [expression]}),
    do: %AST.UnaryOp{op: :deref, expr: lower_expr(expression)}

  defp lower_expr({:tuple_field, _, [expression, index]}) when is_integer(index),
    do: %AST.Field{receiver: lower_expr(expression), field: index}

  defp lower_expr({:some, _, [expression]}),
    do: %AST.Some{expr: lower_wrapper_arg_expr(expression)}

  defp lower_expr({:none, _, []}), do: %AST.None{}
  defp lower_expr({:ok, _, []}), do: %AST.Ok{}
  defp lower_expr({:ok, _, [expression]}), do: %AST.Ok{expr: lower_expr(expression)}
  defp lower_expr({:err, _, [expression]}), do: %AST.Err{expr: lower_expr(expression)}

  defp lower_expr({:token_macro, _, [path, tokens]}),
    do: %AST.TokenMacro{path: lower_token_macro_path(path), tokens: tokens}

  defp lower_expr({:fn, _, [{:->, _, [args, body]}]}), do: lower_closure_args(args, body)

  defp lower_expr({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [collection, mapper]}),
    do: lower_enum_map(collection, mapper)

  defp lower_expr({:expr!, _, [expression]}), do: lower_expr(expression)
  defp lower_expr({:pat!, _, [pattern]}), do: lower_semantic_pat(pattern)
  defp lower_expr({:stmt!, _, [expression]}), do: %AST.ExprStmt{expr: lower_expr(expression)}

  defp lower_expr({:raw_expr!, _, [tokens]}), do: parse_syn(:Expr, tokens)
  defp lower_expr({:raw_pat!, _, [tokens]}), do: parse_syn(:Pat, tokens)
  defp lower_expr({:raw_stmt!, _, [tokens]}), do: parse_syn(:Stmt, tokens)
  defp lower_expr({:raw_arm!, _, [tokens]}), do: parse_syn(:Arm, tokens)

  defp lower_expr({:arm!, _, [pattern, block]}) do
    %AST.Arm{pattern: lower_semantic_pat(pattern), body: lower_semantic_arm_body(block)}
  end

  defp lower_expr({:badarg, _, []}), do: %AST.Path{parts: [:rustler, :Error, :BadArg]}

  defp lower_expr({:struct_literal, _, [path, fields]}),
    do: %AST.StructLiteral{
      path: lower_struct_literal_path(path),
      fields: lower_named_fields(fields)
    }

  defp lower_expr({:array, _, [values]}),
    do: %AST.ArrayLiteral{values: Enum.map(values, &lower_expr/1)}

  defp lower_expr({:index, _, [receiver, index]}),
    do: %AST.Index{receiver: lower_expr(receiver), index: lower_expr(index)}

  defp lower_expr({:==, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :eq, right: lower_expr(right)}

  defp lower_expr({:!=, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :ne, right: lower_expr(right)}

  defp lower_expr({:<, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :lt, right: lower_expr(right)}

  defp lower_expr({:<=, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :lte, right: lower_expr(right)}

  defp lower_expr({:>, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :gt, right: lower_expr(right)}

  defp lower_expr({:>=, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :gte, right: lower_expr(right)}

  defp lower_expr({:+, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :add, right: lower_expr(right)}

  defp lower_expr({:-, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :sub, right: lower_expr(right)}

  defp lower_expr({:*, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :mul, right: lower_expr(right)}

  defp lower_expr({:/, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :div, right: lower_expr(right)}

  defp lower_expr({:and, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :and, right: lower_expr(right)}

  defp lower_expr({:or, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :or, right: lower_expr(right)}

  defp lower_expr({{:., _, [{:__aliases__, _, [:Bitwise]}, :bsr]}, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :shr, right: lower_expr(right)}

  defp lower_expr({{:., _, [{:__aliases__, _, [:Bitwise]}, :band]}, _, [left, right]}),
    do: %AST.BinaryOp{left: lower_expr(left), op: :bitand, right: lower_expr(right)}

  defp lower_expr({:if, _, [condition, branches]}),
    do: lower_if(condition, branches, %Context{position: :expr})

  defp lower_expr({:case, _, [expression, [do: clauses]]}),
    do: lower_case(expression, clauses, %Context{position: :expr})

  defp lower_expr({{:., _meta, [receiver, field_or_function]}, call_meta, []}) do
    no_parens? = Keyword.get(call_meta, :no_parens, false)

    cond do
      no_parens? and alias_path_ast?(receiver) ->
        %AST.Path{parts: alias_path_parts(receiver) ++ [field_or_function]}

      no_parens? ->
        %AST.Field{receiver: lower_expr(receiver), field: field_or_function}

      alias_ast?(receiver) ->
        %AST.PathCall{
          path: %AST.Path{parts: alias_parts(receiver) ++ [field_or_function]},
          args: []
        }

      true ->
        %AST.MethodCall{receiver: lower_expr(receiver), method: field_or_function}
    end
  end

  defp lower_expr({{:., _meta, [receiver, function]}, _, args}) do
    cond do
      super_alias_ast?(receiver) ->
        %AST.PathCall{
          path: %AST.Path{parts: [:super, function]},
          args: lower_call_args(nil, function, args)
        }

      rust_constructor_alias?(receiver) ->
        path = alias_parts(receiver) ++ [rust_variant(function)]

        %AST.PathCall{
          path: %AST.Path{parts: path},
          args: lower_path_call_args(path, function, args)
        }

      alias_ast?(receiver) ->
        path = alias_parts(receiver) ++ [function]

        %AST.PathCall{
          path: %AST.Path{parts: path},
          args: lower_path_call_args(path, function, args)
        }

      true ->
        target = receiver |> infer_expr_type(current_vars()) |> callable_target_from_type()

        %AST.MethodCall{
          receiver: lower_expr(receiver),
          method: function,
          args: lower_call_args(target, function, args)
        }
    end
  end

  defp lower_expr({:__aliases__, _, parts}), do: %AST.Path{parts: mapped_alias_parts(parts)}

  defp lower_expr({:{}, _, values}), do: %AST.Tuple{values: Enum.map(values, &lower_expr/1)}
  defp lower_expr({left, right}), do: %AST.Tuple{values: [lower_expr(left), lower_expr(right)]}

  defp lower_expr({name, _, args}) when is_atom(name) and is_list(args) do
    if macro_call_name?(name) do
      %AST.MacroCall{
        path: %AST.Path{parts: [macro_call_part(name)]},
        args: Enum.map(args, &lower_expr/1)
      }
    else
      %AST.LocalCall{name: name, args: lower_call_args(nil, name, args)}
    end
  end

  defp lower_expr({name, _, context}) when is_atom(name) and is_atom(context),
    do: %AST.Var{name: name}

  defp lower_expr(values) when is_list(values),
    do: %AST.VecLiteral{values: Enum.map(values, &lower_expr/1)}

  defp lower_expr(value) when is_binary(value), do: %AST.Literal{value: value}
  defp lower_expr(value) when is_integer(value) or is_float(value), do: %AST.Literal{value: value}
  defp lower_expr(true), do: %AST.Literal{value: true}
  defp lower_expr(false), do: %AST.Literal{value: false}
  defp lower_expr(nil), do: %AST.None{}
  defp lower_expr(atom) when is_atom(atom), do: %AST.AtomValue{name: atom}

  defp lower_expr(other) do
    Diagnostic.lower(
      :unsupported_expression,
      other,
      "unsupported defrust expression",
      suggestion:
        "Use ordinary Rusty-Elixir forms, add a lowering clause, or use raw_expr! as an explicit escape hatch."
    )
  end

  defp lower_path_call_args(path, function, args) do
    path
    |> path_callable_argument_types(function, length(args))
    |> lower_call_args(args)
  end

  defp lower_call_args(target, function, args) do
    target
    |> callable_argument_types(function, length(args))
    |> lower_call_args(args)
  end

  defp lower_call_args(nil, args), do: Enum.map(args, &lower_expr/1)

  defp lower_call_args(expected_types, args) when is_list(expected_types) do
    args
    |> Enum.zip(expected_types)
    |> Enum.map(fn {arg, expected_type} -> lower_expr(arg, expected_type) end)
  end

  defp callable_argument_types(target, function, arity) do
    BindingIndex.argument_types(current_callables(), target, function, arity)
  end

  defp path_callable_argument_types(path, function, arity) do
    target_parts = Enum.drop(path, -1)

    target_parts
    |> callable_target_candidates()
    |> Enum.find_value(&callable_argument_types(&1, function, arity)) ||
      callable_argument_types(nil, function, arity)
  end

  defp callable_target_from_type(%Type{kind: kind, meta: %{inner: %Type{} = inner}})
       when kind in [:ref, :mut_ref],
       do: callable_target_from_type(inner)

  defp callable_target_from_type(%Type{ast: %AST.TypeRef{inner: inner}}),
    do: callable_target_from_ast(inner)

  defp callable_target_from_type(%Type{meta: %{syn_name: name}}) when is_binary(name), do: name
  defp callable_target_from_type(%Type{ast: ast}), do: callable_target_from_ast(ast)
  defp callable_target_from_type(_type), do: nil

  defp callable_target_from_ast(%AST.TypePath{parts: [_ | _] = parts}),
    do: parts |> List.last() |> to_string()

  defp callable_target_from_ast(_ast), do: nil

  defp decode_as_expr(expression, type_ast) do
    %AST.MethodCall{
      receiver: lower_expr(expression),
      method: :decode,
      args: [],
      generics: [RustQ.Spec.type(type_ast).ast]
    }
  end

  defp lower_pipe(left, right) do
    lower_pipe_call(lower_expr(left), right)
  end

  defp lower_pipe_call(receiver, {:cast, _, [type]}),
    do: %AST.Cast{expr: receiver, type: RustQ.Spec.type(type).ast}

  defp lower_pipe_call(receiver, {{:., _, [{:__aliases__, _, [:Kernel]}, operator]}, _, [right]})
       when operator in [:+, :-, :*, :/] do
    %AST.BinaryOp{left: receiver, op: operator_op(operator), right: lower_expr(right)}
  end

  defp lower_pipe_call(receiver, {name, _, args}) when is_atom(name) and is_list(args) do
    %AST.MethodCall{receiver: receiver, method: name, args: Enum.map(args, &lower_expr/1)}
  end

  defp lower_pipe_call(_receiver, other) do
    Diagnostic.lower(
      :unsupported_pipeline_step,
      other,
      "unsupported defrust pipeline step",
      suggestion: "Pipe into a method call, cast/1, or add an explicit lowering clause."
    )
  end

  defp operator_op(:+), do: :add
  defp operator_op(:-), do: :sub
  defp operator_op(:*), do: :mul
  defp operator_op(:/), do: :div

  defp lower_enum_map(collection, {:fn, _, [{:->, _, [args, body]}]}) do
    collection
    |> lower_expr()
    |> method_chain(:into_iter)
    |> method_chain(:map, [lower_closure_args(args, body)])
    |> method_chain(:collect)
  end

  defp lower_enum_map(_collection, other) do
    Diagnostic.lower(
      :unsupported_enum_map_mapper,
      other,
      "unsupported Enum.map mapper in defrust",
      suggestion: "Use an anonymous function mapper, e.g. Enum.map(values, fn value -> ... end)."
    )
  end

  defp lower_closure_args(args, body) when is_list(args),
    do: %AST.Closure{
      args: Enum.map(args, &closure_arg!/1),
      body: lower_expr(closure_body_expr(body))
    }

  defp closure_arg!({name, _, context}) when is_atom(name) and is_atom(context), do: name

  defp closure_arg!(other) do
    Diagnostic.lower(
      :unsupported_closure_argument,
      other,
      "unsupported defrust closure argument",
      suggestion: "Use a plain variable as the closure argument."
    )
  end

  defp closure_body_expr([expression]), do: expression
  defp closure_body_expr(expression), do: expression

  defp method_chain(receiver, method, args \\ []),
    do: %AST.MethodCall{receiver: receiver, method: method, args: args}

  defp macro_call_name?(name), do: name |> Atom.to_string() |> String.ends_with?("!")

  defp macro_call_part(name) do
    RustQ.Atom.identifier!(String.trim_trailing(Atom.to_string(name), "!"))
  end

  defp lower_nif_error(atom) when is_atom(atom), do: %AST.NifRaiseAtom{name: atom}
  defp lower_nif_error(other), do: lower_expr(other)

  defp lower_semantic_pat({:ident, _, [name]}), do: %AST.PatVar{name: semantic_atom!(name)}

  defp lower_semantic_pat({:mut_ident, _, [name]}),
    do: %AST.PatVar{name: semantic_atom!(name), mutable: true}

  defp lower_semantic_pat({:path, _, [path]}), do: %AST.PatPath{path: lower_expr_path(path)}

  defp lower_semantic_pat({:some, _, [pattern]}),
    do: %AST.PatSome{pattern: lower_semantic_pat(pattern)}

  defp lower_semantic_pat({:ok, pattern}), do: %AST.PatOk{pattern: lower_semantic_pat(pattern)}

  defp lower_semantic_pat({:error, pattern}),
    do: %AST.PatErr{pattern: lower_semantic_pat(pattern)}

  defp lower_semantic_pat({:{}, _, [:ok, pattern]}),
    do: %AST.PatOk{pattern: lower_semantic_pat(pattern)}

  defp lower_semantic_pat({:{}, _, [:error, pattern]}),
    do: %AST.PatErr{pattern: lower_semantic_pat(pattern)}

  defp lower_semantic_pat({:tuple, _, [patterns]}),
    do: %AST.PatTuple{patterns: Enum.map(patterns, &lower_semantic_pat/1)}

  defp lower_semantic_pat({:path_tuple, _, [path, patterns]}),
    do: %AST.PatPathTuple{
      path: lower_expr_path(path),
      patterns: Enum.map(patterns, &lower_semantic_pat/1)
    }

  defp lower_semantic_pat({:struct, _, [path, fields]}),
    do: %AST.PatStruct{path: lower_expr_path(path), fields: lower_semantic_pat_fields(fields)}

  defp lower_semantic_pat(nil), do: %AST.PatNone{}
  defp lower_semantic_pat(:_), do: %AST.PatWildcard{}
  defp lower_semantic_pat({:_, _, _}), do: %AST.PatWildcard{}
  defp lower_semantic_pat(other), do: lower_match_pattern(other, nil)

  defp lower_semantic_pat_fields(fields) when is_list(fields) do
    Enum.map(fields, fn {name, pattern} -> {name, lower_semantic_pat(pattern)} end)
  end

  defp lower_semantic_arm_body(body),
    do: lower_clause_body(body, %Context{position: :return})

  defp lower_expr_path(%AST.Path{} = path), do: path

  defp lower_expr_path(expression) do
    case lower_expr(expression) do
      %AST.Path{} = path ->
        path

      other ->
        Diagnostic.lower(
          :expected_rust_path,
          expression,
          "expected Rust path, got: #{inspect(other)}"
        )
    end
  end

  defp semantic_atom!(atom) when is_atom(atom), do: atom
  defp semantic_atom!({name, _, context}) when is_atom(name) and is_atom(context), do: name

  defp semantic_atom!(other) do
    Diagnostic.lower(:expected_atom_identifier, other, "expected atom identifier")
  end

  defp parse_syn(type, tokens) do
    %AST.PathCall{
      path: %AST.Path{parts: [:super, "parse_syn::<#{type}>"]},
      args: [quote_tokens(tokens)]
    }
  end

  defp quote_tokens(tokens) when is_binary(tokens),
    do: %AST.TokenMacro{path: %AST.Path{parts: [:quote]}, tokens: tokens}

  defp quote_tokens(other) do
    Diagnostic.lower(
      :unsupported_quote_tokens,
      other,
      "unsupported quote tokens",
      suggestion: "Pass a literal binary token string to raw_expr!/raw_pat!/raw_stmt!/raw_arm!."
    )
  end

  defp lower_struct_literal_path(path), do: lower_expr(path)

  defp lower_named_fields(fields) when is_list(fields) do
    Enum.map(fields, fn {name, expression} -> {name, lower_expr(expression)} end)
  end

  defp lower_token_macro_path(atom) when is_atom(atom), do: %AST.Path{parts: [atom]}
  defp lower_token_macro_path({:__aliases__, _, parts}), do: %AST.Path{parts: parts}

  defp lower_token_macro_path(other) do
    Diagnostic.lower(
      :unsupported_token_macro_path,
      other,
      "unsupported token_macro path",
      suggestion: "Use an atom or alias as the token macro path."
    )
  end

  defp infer_let_expected_type(pattern, expression, vars) do
    infer_pattern_type(pattern, vars) || infer_pattern_type_from_call(pattern, expression)
  end

  defp infer_pattern_type({name, _, context}, vars) when is_atom(name) and is_atom(context),
    do: Map.get(vars, name)

  defp infer_pattern_type(_pattern, _vars), do: nil

  defp infer_pattern_type_from_call(pattern, expression) do
    with [_ | _] = elements <- tuple_pattern_elements(pattern),
         %Type{} = call_type <- callable_return_type(expression),
         true <- Type.propagates?(call_type),
         %Type{kind: :tuple, meta: %{elements: types}} = inner <- Type.inner(call_type),
         true <- length(elements) == length(types) do
      inner
    else
      _no_tuple_match -> nil
    end
  end

  defp tuple_pattern_elements({:{}, _, elements}) when is_list(elements), do: elements

  defp tuple_pattern_elements(pattern)
       when is_tuple(pattern) and tuple_size(pattern) != 3,
       do: Tuple.to_list(pattern)

  defp tuple_pattern_elements(_pattern), do: nil

  defp infer_expr_type({name, _, context}, vars) when is_atom(name) and is_atom(context),
    do: Map.get(vars, name)

  defp infer_expr_type(_expression, _vars), do: nil

  defp context_with_downstream_let_types(expressions, %Context{} = context) do
    %{
      context
      | vars: Map.merge(context.vars, infer_downstream_let_types(expressions, context.vars))
    }
  end

  defp infer_downstream_let_types(expressions, vars) do
    expressions
    |> Stream.with_index()
    |> Enum.reduce({%{}, vars}, fn {expression, index}, {inferred, known_vars} ->
      new_inferred = infer_downstream_let_type(expression, expressions, index, known_vars)
      next_known_vars = Map.merge(known_vars, inferred_binding_types(expression, new_inferred))
      {Map.merge(inferred, new_inferred), next_known_vars}
    end)
    |> elem(0)
  end

  defp infer_downstream_let_type({:=, _, [{name, _, context}, _rhs]}, expressions, index, vars)
       when is_atom(name) and is_atom(context) do
    expressions
    |> Enum.drop(index + 1)
    |> Enum.find_value(&expected_type_for_var(name, &1, vars))
    |> case do
      %Type{} = type -> %{name => type}
      nil -> %{}
    end
  end

  defp infer_downstream_let_type(_expression, _expressions, _index, _vars), do: %{}

  defp inferred_binding_types({:=, _, [{name, _, context}, rhs]}, inferred)
       when is_atom(name) and is_atom(context) do
    case Map.fetch(inferred, name) do
      {:ok, %Type{} = type} -> %{name => type}
      :error -> inferred_binding_type_from_rhs(name, rhs)
    end
  end

  defp inferred_binding_types(_expression, _inferred), do: %{}

  defp inferred_binding_type_from_rhs(name, {:unwrap!, _, [call]}) do
    case callable_return_type(call) do
      %Type{} = type -> %{name => Type.inner(type) || type}
      nil -> %{}
    end
  end

  defp inferred_binding_type_from_rhs(name, call) do
    case callable_return_type(call) do
      %Type{} = type -> %{name => type}
      nil -> %{}
    end
  end

  defp expected_type_for_var(name, ast, vars) do
    ast
    |> downstream_call_arg_types(vars)
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
       do: expected_value_type_for_argument(type)

  defp expected_type_for_arg_expr(
         name,
         {{:., _, [{var_name, _, context}, :as_ref]}, _meta, []},
         %Type{} = type
       )
       when name == var_name and is_atom(context),
       do: receiver_type_for_as_ref_argument(type)

  defp expected_type_for_arg_expr(name, tuple, %Type{} = type) do
    expected_type_for_tuple_arg(name, tuple, expected_value_type_for_argument(type))
  end

  defp expected_type_for_arg_expr(_name, _arg, _expected_type), do: nil

  defp expected_type_for_tuple_arg(name, tuple, %Type{kind: :tuple, meta: %{elements: types}}) do
    case tuple_pattern_elements(tuple) do
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

  defp expected_value_type_for_argument(%Type{kind: :impl_trait, meta: %{traits: traits}} = type) do
    traits
    |> Enum.find_value(fn
      %Type{meta: %{syn_name: "Into", args: [inner]}} -> expected_value_type_for_argument(inner)
      _trait -> nil
    end) || type
  end

  defp expected_value_type_for_argument(%Type{
         kind: :option,
         meta: %{inner: %Type{kind: :tuple} = inner}
       }),
       do: inner

  defp expected_value_type_for_argument(%Type{} = type), do: type

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

  defp downstream_call_arg_types(ast, vars) do
    {_ast, calls} = Macro.prewalk(ast, [], &collect_downstream_call_arg_types(&1, &2, vars))
    calls
  end

  defp collect_downstream_call_arg_types({name, _meta, args} = ast, calls, _vars)
       when is_atom(name) and is_list(args) do
    {ast,
     maybe_add_downstream_call(calls, args, callable_argument_types(nil, name, length(args)))}
  end

  defp collect_downstream_call_arg_types(
         {{:., _, [{:__aliases__, _, parts}, function]}, _meta, args} = ast,
         calls,
         _vars
       )
       when is_atom(function) and is_list(args) do
    path = alias_parts({:__aliases__, [], parts}) ++ [function]

    {ast,
     maybe_add_downstream_call(
       calls,
       args,
       path_callable_argument_types(path, function, length(args))
     )}
  end

  defp collect_downstream_call_arg_types(
         {{:., _, [receiver, function]}, _meta, args} = ast,
         calls,
         vars
       )
       when is_atom(function) and is_list(args) do
    target = receiver |> infer_expr_type(vars) |> callable_target_from_type()

    {ast,
     maybe_add_downstream_call(
       calls,
       args,
       callable_argument_types(target, function, length(args))
     )}
  end

  defp collect_downstream_call_arg_types(ast, calls, _vars), do: {ast, calls}

  defp maybe_add_downstream_call(calls, args, [_ | _] = expected_types),
    do: [{args, expected_types} | calls]

  defp maybe_add_downstream_call(calls, _args, _expected_types), do: calls

  defp infer_mutability(body) do
    mutable_vars = body |> collect_mutable_let_refs() |> MapSet.new()
    Enum.map(body, &mark_mutable_lets(&1, mutable_vars))
  end

  defp mark_mutable_lets(%AST.Let{pattern: %AST.PatVar{name: name}} = let, mutable_vars) do
    %{
      let
      | mutable: MapSet.member?(mutable_vars, name),
        expr: mark_mutable_expr(let.expr, mutable_vars)
    }
  end

  defp mark_mutable_lets(%AST.Let{} = let, mutable_vars),
    do: %{let | expr: mark_mutable_expr(let.expr, mutable_vars)}

  defp mark_mutable_lets(%AST.Assign{} = stmt, mutable_vars),
    do: %{
      stmt
      | target: mark_mutable_expr(stmt.target, mutable_vars),
        expr: mark_mutable_expr(stmt.expr, mutable_vars)
    }

  defp mark_mutable_lets(%AST.ExprStmt{} = stmt, mutable_vars),
    do: %{stmt | expr: mark_mutable_expr(stmt.expr, mutable_vars)}

  defp mark_mutable_lets(%AST.Return{} = stmt, mutable_vars),
    do: %{stmt | expr: mark_mutable_expr(stmt.expr, mutable_vars)}

  defp mark_mutable_lets(%AST.EarlyReturn{} = stmt, mutable_vars),
    do: %{stmt | expr: mark_mutable_expr(stmt.expr, mutable_vars)}

  defp mark_mutable_lets(%AST.For{} = stmt, mutable_vars) do
    %{
      stmt
      | expr: mark_mutable_expr(stmt.expr, mutable_vars),
        body: Enum.map(stmt.body, &mark_mutable_lets(&1, mutable_vars))
    }
  end

  defp mark_mutable_expr(%AST.Match{} = match, mutable_vars) do
    arms =
      Enum.map(match.arms, fn %AST.Arm{} = arm ->
        %{arm | body: Enum.map(arm.body, &mark_mutable_lets(&1, mutable_vars))}
      end)

    %{match | expr: mark_mutable_expr(match.expr, mutable_vars), arms: arms}
  end

  defp mark_mutable_expr(%AST.If{} = expr, mutable_vars) do
    %{
      expr
      | condition: mark_mutable_expr(expr.condition, mutable_vars),
        then: Enum.map(expr.then, &mark_mutable_lets(&1, mutable_vars)),
        else: Enum.map(expr.else, &mark_mutable_lets(&1, mutable_vars))
    }
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

  defp mark_mutable_expr_fallback(%AST.MacroCall{} = expr, mutable_vars),
    do: %{expr | args: Enum.map(expr.args, &mark_mutable_expr(&1, mutable_vars))}

  defp mark_mutable_expr_fallback(%AST.Field{} = expr, mutable_vars),
    do: %{expr | receiver: mark_mutable_expr(expr.receiver, mutable_vars)}

  defp mark_mutable_expr_fallback(%AST.Index{} = expr, mutable_vars),
    do: %{
      expr
      | receiver: mark_mutable_expr(expr.receiver, mutable_vars),
        index: mark_mutable_expr(expr.index, mutable_vars)
    }

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

  defp collect_mutable_let_refs(term), do: do_collect_mutable_let_refs(term, [])

  defp do_collect_mutable_let_refs(
         %AST.ExprStmt{expr: %AST.MethodCall{receiver: %AST.Var{name: name}}} = stmt,
         acc
       ) do
    do_collect_mutable_let_refs(stmt.expr, [name | acc])
  end

  defp do_collect_mutable_let_refs(%AST.Assign{target: %AST.Var{name: name}} = assign, acc) do
    do_collect_mutable_let_refs(assign.expr, [name | acc])
  end

  defp do_collect_mutable_let_refs(
         %AST.Assign{target: %AST.Index{receiver: %AST.Var{name: name}}} = assign,
         acc
       ) do
    do_collect_mutable_let_refs(assign.expr, [name | acc])
  end

  defp do_collect_mutable_let_refs(%AST.Ref{mutable: true, expr: %AST.Var{name: name}} = ref, acc) do
    do_collect_mutable_let_refs(ref.expr, [name | acc])
  end

  defp do_collect_mutable_let_refs(%{__struct__: _struct} = term, acc) do
    term
    |> Map.from_struct()
    |> Map.values()
    |> Enum.reduce(acc, &do_collect_mutable_let_refs/2)
  end

  defp do_collect_mutable_let_refs(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &do_collect_mutable_let_refs/2)

  defp do_collect_mutable_let_refs(_other, acc), do: acc

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

  defp alias_path_ast?({:__aliases__, _, _parts}), do: true

  defp alias_path_ast?({{:., _, [receiver, _field]}, meta, []}),
    do: Keyword.get(meta, :no_parens, false) and alias_path_ast?(receiver)

  defp alias_path_ast?(_other), do: false

  defp super_alias_ast?({:__aliases__, _, [:Super]}), do: true
  defp super_alias_ast?(_other), do: false

  defp rust_constructor_alias?({:__aliases__, _, [module]}) when module in [:Stmt], do: true
  defp rust_constructor_alias?(_other), do: false

  defp rust_variant(name), do: RustQ.Atom.identifier!(Macro.camelize(Atom.to_string(name)))

  defp alias_parts({:__aliases__, _, parts}),
    do: mapped_alias_parts(parts)

  defp alias_path_parts(ast), do: ast |> raw_alias_path_parts() |> mapped_alias_parts()

  defp raw_alias_path_parts(ast), do: raw_alias_path_parts(ast, [])

  defp raw_alias_path_parts({:__aliases__, _, parts}, acc) do
    parts
    |> Enum.reverse()
    |> Enum.reduce(acc, &[&1 | &2])
  end

  defp raw_alias_path_parts({{:., _, [receiver, field]}, meta, []} = ast, acc) do
    if Keyword.get(meta, :no_parens, false) do
      raw_alias_path_parts(receiver, [field | acc])
    else
      Diagnostic.lower(:unsupported_alias_path, ast, "unsupported alias path")
    end
  end

  defp mapped_alias_parts(parts) do
    modules = current_rust_modules()

    parts
    |> alias_prefixes()
    |> Enum.find_value(fn {prefix, suffix} ->
      mapped = Map.get(modules, prefix)
      if mapped, do: mapped ++ suffix
    end) || automatic_rust_alias_parts(parts)
  end

  defp alias_prefixes(parts) do
    parts
    |> length()
    |> Range.new(1, -1)
    |> Enum.map(fn count -> Enum.split(parts, count) end)
  end

  defp automatic_rust_alias_parts(parts) do
    if rust_module_alias?(parts) do
      Enum.map(parts, &rust_module_part/1)
    else
      parts
    end
  end

  defp rust_module_alias?(parts) do
    parts
    |> List.last()
    |> Atom.to_string()
    |> String.ends_with?("s")
  end

  defp rust_module_part(part),
    do: RustQ.Atom.identifier!(Macro.underscore(Atom.to_string(part)))

  defp callable_return_type_from_index({name, _meta, args}, %BindingIndex{} = callables)
       when is_atom(name) and is_list(args) do
    BindingIndex.return_type(callables, nil, name, length(args))
  end

  defp callable_return_type_from_index(
         {{:., _, [{:__aliases__, _, parts}, function]}, _meta, args},
         %BindingIndex{} = callables
       )
       when is_atom(function) and is_list(args) do
    arity = length(args)

    parts
    |> callable_return_type_for_path(function, arity, callables)
  end

  defp callable_return_type_from_index(_call_ast, %BindingIndex{}), do: nil

  defp callable_return_type_for_path(parts, function, arity, callables) do
    parts
    |> callable_target_candidates()
    |> Enum.find_value(&BindingIndex.return_type(callables, &1, function, arity)) ||
      BindingIndex.return_type(callables, nil, function, arity)
  end

  defp callable_target_candidates(parts) do
    mapped = mapped_alias_parts(parts)
    mapped_last = List.last(mapped)
    parts_last = List.last(parts)

    [
      Enum.map_join(mapped, "::", &to_string/1),
      to_string(mapped_last),
      singular_candidate(mapped_last),
      singular_module_candidate(mapped_last),
      Enum.map_join(parts, "::", &to_string/1),
      to_string(parts_last),
      singular_candidate(parts_last),
      singular_module_candidate(parts_last)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp singular_candidate(part) when is_atom(part),
    do: part |> to_string() |> singular_candidate()

  defp singular_candidate(part) when is_binary(part) do
    if String.ends_with?(part, "s") and String.length(part) > 1 do
      String.trim_trailing(part, "s")
    end
  end

  defp singular_candidate(_part), do: nil

  defp singular_module_candidate(part) do
    case singular_candidate(part) do
      nil -> nil
      singular -> Macro.camelize(singular)
    end
  end

  defp with_lowering_context(%Context{} = context, fun) do
    values = [
      rust_modules: context.rust_modules,
      callables: context.callables,
      vars: context.vars,
      return_type: context.return_type
    ]

    with_process_values(values, fun)
  end

  defp with_process_values(values, fun) do
    previous = Map.new(values, fn {name, value} -> {name, put_process_value(name, value)} end)

    try do
      fun.()
    after
      Enum.each(previous, fn {name, value} -> restore_process_value(name, value) end)
    end
  end

  defp put_process_value(name, value) do
    key = {__MODULE__, name}
    previous = Process.get(key)
    Process.put(key, value)
    previous
  end

  defp restore_process_value(name, nil), do: Process.delete({__MODULE__, name})
  defp restore_process_value(name, value), do: Process.put({__MODULE__, name}, value)

  defp current_rust_modules, do: Process.get({__MODULE__, :rust_modules}, %{})
  defp current_callables, do: Process.get({__MODULE__, :callables}, %BindingIndex{})
  defp current_vars, do: Process.get({__MODULE__, :vars}, %{})
  defp current_return_type, do: Process.get({__MODULE__, :return_type})
end
