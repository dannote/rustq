defmodule RustQ.Meta.Lower do
  @moduledoc false

  alias RustQ.Meta.Type

  @spec function_body(Macro.t(), Type.t()) :: String.t()
  def function_body(body_ast, return_type) do
    body_ast
    |> block_expressions()
    |> lower_block(return_type)
  end

  defp lower_block(expressions, return_type) do
    {statements, final} = split_final(expressions)

    statements = Enum.map(statements, &lower_statement/1)
    final = lower_return(final, return_type)

    (statements ++ [final])
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp split_final([]), do: {[], :ok}
  defp split_final(expressions), do: {Enum.drop(expressions, -1), List.last(expressions)}

  defp block_expressions({:__block__, _, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]

  defp lower_statement({:=, _, [pattern, expression]}) do
    "let #{lower_binding_pattern(pattern)} = #{lower_expr(expression)};"
  end

  defp lower_statement({:case, _, [expression, [do: clauses]]}) do
    lower_case(expression, clauses, :statement)
  end

  defp lower_statement(:ok), do: ""
  defp lower_statement(nil), do: ""

  defp lower_statement(expression) do
    lower_expr(expression) <> ";"
  end

  defp lower_return({:case, _, [expression, [do: clauses]]}, return_type) do
    lower_case(expression, clauses, {:return, return_type})
  end

  defp lower_return(:ok, %Type{kind: :nif_result, rust: "NifResult<()>"}), do: "Ok(())"
  defp lower_return(:ok, _return_type), do: "()"
  defp lower_return(nil, %Type{kind: :option}), do: "None"

  defp lower_return({:ok, value}, %Type{kind: kind}) when kind in [:result, :nif_result] do
    "Ok(#{lower_expr(value)})"
  end

  defp lower_return({:error, value}, %Type{kind: :nif_result}) do
    "Err(#{lower_nif_error(value)})"
  end

  defp lower_return({:error, value}, %Type{kind: :result}) do
    "Err(#{lower_expr(value)})"
  end

  defp lower_return(expression, %Type{kind: :option}) do
    "Some(#{lower_expr(expression)})"
  end

  defp lower_return(expression, _return_type), do: lower_expr(expression)

  defp lower_case(expression, clauses, context) do
    option_case? = Enum.any?(clauses, fn {:->, _, [[pattern], _body]} -> pattern == nil end)

    arms =
      clauses
      |> Enum.map(fn {:->, _, [[pattern], body]} ->
        pattern = lower_match_pattern(pattern, option_case?)
        body = lower_clause_body(body, context)
        "#{pattern} => {\n#{indent(body)}\n},"
      end)
      |> Enum.join("\n")

    "match #{lower_expr(expression)} {\n#{indent(arms)}\n}"
  end

  defp lower_clause_body(body, :statement) do
    body
    |> block_expressions()
    |> Enum.map(&lower_statement/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp lower_clause_body(body, {:return, return_type}) do
    body
    |> block_expressions()
    |> lower_block(return_type)
  end

  defp lower_binding_pattern({name, _, context}) when is_atom(name) and is_atom(context), do: name

  defp lower_binding_pattern(other) do
    raise ArgumentError, "unsupported defrust binding pattern: #{Macro.to_string(other)}"
  end

  defp lower_match_pattern(nil, _option_case?), do: "None"
  defp lower_match_pattern({:_, _, _}, _option_case?), do: "_"

  defp lower_match_pattern({name, _, context}, true) when is_atom(name) and is_atom(context),
    do: "Some(#{name})"

  defp lower_match_pattern({name, _, context}, false) when is_atom(name) and is_atom(context),
    do: Atom.to_string(name)

  defp lower_match_pattern(atom, _option_case?) when is_atom(atom) do
    "value if value == atoms::#{atom}()"
  end

  defp lower_match_pattern({:{}, _, values}, _option_case?) do
    "(" <> Enum.map_join(values, ", ", &lower_tuple_pattern/1) <> ")"
  end

  defp lower_match_pattern(other, _option_case?) do
    raise ArgumentError, "unsupported defrust match pattern: #{Macro.to_string(other)}"
  end

  defp lower_tuple_pattern({name, _, context}) when is_atom(name) and is_atom(context),
    do: Atom.to_string(name)

  defp lower_tuple_pattern({:_, _, _}), do: "_"
  defp lower_tuple_pattern(nil), do: "None"
  defp lower_tuple_pattern(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp lower_expr({:unwrap!, _, [expression]}), do: lower_expr(expression) <> "?"
  defp lower_expr({:ref, _, [expression]}), do: "&" <> lower_expr(expression)
  defp lower_expr({:mut_ref, _, [expression]}), do: "&mut " <> lower_expr(expression)
  defp lower_expr({:some, _, [expression]}), do: "Some(#{lower_expr(expression)})"
  defp lower_expr({:none, _, []}), do: "None"
  defp lower_expr({:ok, _, []}), do: "Ok(())"
  defp lower_expr({:ok, _, [expression]}), do: "Ok(#{lower_expr(expression)})"
  defp lower_expr({:err, _, [expression]}), do: "Err(#{lower_expr(expression)})"

  defp lower_expr({{:., _meta, [receiver, field_or_function]}, call_meta, []}) do
    cond do
      Keyword.get(call_meta, :no_parens) ->
        lower_expr(receiver) <> "." <> Atom.to_string(field_or_function)

      alias_ast?(receiver) ->
        lower_expr({:__aliases__, [], alias_parts(receiver) ++ [field_or_function]})

      true ->
        lower_expr(receiver) <> "." <> Atom.to_string(field_or_function) <> "()"
    end
  end

  defp lower_expr({{:., _meta, [receiver, function]}, _, args}) do
    rendered_args = Enum.map_join(args, ", ", &lower_expr/1)

    if alias_ast?(receiver) do
      lower_expr(receiver) <> "::" <> Atom.to_string(function) <> "(" <> rendered_args <> ")"
    else
      lower_expr(receiver) <> "." <> Atom.to_string(function) <> "(" <> rendered_args <> ")"
    end
  end

  defp lower_expr({:__aliases__, _, parts}), do: Enum.map_join(parts, "::", &to_string/1)

  defp lower_expr({name, _, args}) when is_atom(name) and is_list(args) do
    Atom.to_string(name) <> "(" <> Enum.map_join(args, ", ", &lower_expr/1) <> ")"
  end

  defp lower_expr({name, _, context}) when is_atom(name) and is_atom(context),
    do: Atom.to_string(name)

  defp lower_expr({:{}, _, values}), do: "(" <> Enum.map_join(values, ", ", &lower_expr/1) <> ")"
  defp lower_expr(value) when is_binary(value), do: inspect(value)
  defp lower_expr(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp lower_expr(true), do: "true"
  defp lower_expr(false), do: "false"
  defp lower_expr(nil), do: "None"
  defp lower_expr(atom) when is_atom(atom), do: "atoms::#{atom}()"

  defp lower_expr(other) do
    raise ArgumentError, "unsupported defrust expression: #{Macro.to_string(other)}"
  end

  defp lower_nif_error(atom) when is_atom(atom) do
    ~s|rustler::Error::RaiseAtom("#{atom}")|
  end

  defp lower_nif_error(other), do: lower_expr(other)

  defp alias_ast?({:__aliases__, _, _parts}), do: true
  defp alias_ast?(_other), do: false

  defp alias_parts({:__aliases__, _, parts}), do: parts

  defp indent(code) do
    code
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end
end
