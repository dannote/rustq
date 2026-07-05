defmodule RustQ.Rust.AST.Walk do
  @moduledoc """
  Generic traversal helpers for RustQ AST nodes.

  Traversal is driven by RustQ AST node structs, so passes do not need to
  hand-maintain structural recursion every time a node gains a field.
  """

  alias RustQ.Rust.AST

  @type ast_node :: struct()
  @doc """
  Walks an AST tree in pre-order, applying `fun` before children are visited.
  """
  @spec prewalk(term(), (term() -> term())) :: term()
  def prewalk(term, fun) when is_function(fun, 1) do
    term
    |> fun.()
    |> walk_children(:pre, fun)
  end

  @doc """
  Walks an AST tree in post-order, applying `fun` after children are visited.
  """
  @spec postwalk(term(), (term() -> term())) :: term()
  def postwalk(term, fun) when is_function(fun, 1) do
    term
    |> walk_children(:post, fun)
    |> fun.()
  end

  @doc """
  Reduces an AST tree in pre-order.
  """
  @spec reduce(term(), acc, (term(), acc -> acc)) :: acc when acc: term()
  def reduce(term, acc, fun) when is_function(fun, 2) do
    term
    |> fun.(acc)
    |> reduce_children(term, fun)
  end

  @doc """
  Returns true when `term` is one of RustQ's schema-backed AST nodes.
  """
  @spec node?(term()) :: boolean()
  def node?(%{__struct__: module}), do: Map.has_key?(node_fields(), module)
  def node?(_term), do: false

  defp walk(term, :pre, fun), do: prewalk(term, fun)
  defp walk(term, :post, fun), do: postwalk(term, fun)

  defp reduce_children(acc, %{__struct__: module} = node, fun) do
    case Map.fetch(node_fields(), module) do
      {:ok, fields} ->
        Enum.reduce(fields, acc, fn field, acc ->
          reduce(Map.fetch!(node, field), acc, fun)
        end)

      :error ->
        acc
    end
  end

  defp reduce_children(acc, list, fun) when is_list(list) do
    Enum.reduce(list, acc, &reduce(&1, &2, fun))
  end

  defp reduce_children(acc, tuple, fun) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(acc, &reduce(&1, &2, fun))
  end

  defp reduce_children(acc, _term, _fun), do: acc

  defp node_fields do
    AST.__rustq_ast_modules__()
    |> Map.new(fn module -> {module, struct_fields(module)} end)
  end

  defp struct_fields(module) do
    module
    |> struct()
    |> Map.from_struct()
    |> Map.keys()
  end

  defp walk_children(%{__struct__: module} = node, order, fun) do
    case Map.fetch(node_fields(), module) do
      {:ok, fields} ->
        Enum.reduce(fields, node, fn field, acc ->
          Map.update!(acc, field, &walk(&1, order, fun))
        end)

      :error ->
        node
    end
  end

  defp walk_children(list, order, fun) when is_list(list) do
    Enum.map(list, &walk(&1, order, fun))
  end

  defp walk_children(tuple, order, fun) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&walk(&1, order, fun))
    |> List.to_tuple()
  end

  defp walk_children(term, _order, _fun), do: term
end
