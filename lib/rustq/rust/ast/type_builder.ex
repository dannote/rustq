defmodule RustQ.Rust.AST.TypeBuilder do
  @moduledoc """
  Small constructor API for RustQ type AST nodes.
  """

  alias RustQ.Rust.AST

  def type(%{__struct__: _module} = value) do
    if AST.type_node?(value) do
      value
    else
      raise ArgumentError, "expected RustQ type AST node, got: #{inspect(value)}"
    end
  end

  def type(parts) when is_list(parts), do: path(parts)
  def type(part) when is_atom(part) or is_binary(part), do: path(part)
  def type({:raw, _source} = raw), do: raw

  def path(parts_or_part, opts \\ [])

  def path(parts, opts) when is_list(parts),
    do: %AST.TypePath{
      parts: parts,
      lifetimes: Keyword.get(opts, :lifetimes, []),
      generics: Keyword.get(opts, :generics, [])
    }

  def path(part, opts) when is_atom(part), do: path([part], opts)

  def path(part, opts) when is_binary(part) do
    part
    |> String.split("::")
    |> path(opts)
  end

  def unit, do: %AST.TypeUnit{}
  def nif_result(inner), do: %AST.TypeNifResult{inner: type(inner)}
  def vec(inner), do: %AST.TypeVec{inner: type(inner)}

  def ref(inner, opts \\ []),
    do: %AST.TypeRef{inner: type(inner), lifetime: Keyword.get(opts, :lifetime)}

  def mut_ref(inner, opts \\ []),
    do: %AST.TypeRef{inner: type(inner), mutable: true, lifetime: Keyword.get(opts, :lifetime)}

  def term(lifetime \\ :a), do: %AST.TypePath{parts: [:Term], lifetimes: List.wrap(lifetime)}
end
