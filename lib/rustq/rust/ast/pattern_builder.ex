defmodule RustQ.Rust.AST.PatternBuilder do
  @moduledoc """
  Small constructor API for RustQ pattern AST nodes.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  def pattern(%{__struct__: _module} = value) do
    if AST.pat_node?(value) do
      value
    else
      raise ArgumentError, "expected RustQ pattern AST node, got: #{inspect(value)}"
    end
  end

  def pattern(name) when is_atom(name), do: var(name)

  def var(name) when is_atom(name), do: %AST.PatVar{name: name}
  def wildcard, do: %AST.PatWildcard{}
  def path(path), do: %AST.PatPath{path: A.expr_path(path)}
  def lit(value), do: %AST.PatLiteral{value: value}
  def none, do: %AST.PatNone{}
  def some(pattern), do: %AST.PatSome{pattern: pattern(pattern)}
  def ok(pattern), do: %AST.PatOk{pattern: pattern(pattern)}
  def err(pattern), do: %AST.PatErr{pattern: pattern(pattern)}

  def path_tuple(path, patterns),
    do: %AST.PatPathTuple{path: A.expr_path(path), patterns: Enum.map(patterns, &pattern/1)}

  def struct(path, fields) do
    %AST.PatStruct{
      path: A.expr_path(path),
      fields: Enum.map(fields, fn {name, pattern} -> {name, pattern(pattern)} end)
    }
  end
end
