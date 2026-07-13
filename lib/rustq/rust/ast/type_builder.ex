defmodule RustQ.Rust.AST.TypeBuilder do
  @moduledoc """
  Constructors and normalization for Rust type AST nodes.

  `type/1` accepts existing type nodes, Rust paths, and structural tuples such
  as `{:option, type}`, `{:result, ok, error}`, `{:vec, type}`, references,
  slices, arrays, and explicit `{:raw, source}` escapes. Prefer the named
  constructors when they make generator intent clearer.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render

  def type(%{__struct__: _module} = value) do
    if AST.type_node?(value) do
      value
    else
      raise ArgumentError, "expected RustQ type AST node, got: #{inspect(value)}"
    end
  end

  def type(parts) when is_list(parts), do: path(parts)
  def type(part) when is_atom(part) or is_binary(part), do: path(part)
  def type({:raw, source}), do: raw(source)
  def type({:path, parts}), do: path(parts)
  def type({:path, parts, generics}), do: path(parts, generics: Enum.map(generics, &type/1))
  def type({:ref, opts}) when is_list(opts), do: ref(Keyword.fetch!(opts, :type), opts)
  def type({:ref, inner}), do: ref(inner)
  def type({:mut_ref, inner}), do: mut_ref(inner)
  def type({:option, inner}), do: option(inner)
  def type({:result, ok, error}), do: result(ok, error)
  def type({:nif_result, inner}), do: nif_result(inner)
  def type({:vec, inner}), do: vec(inner)
  def type({:slice, inner}), do: slice(inner)
  def type({:array, inner, size}), do: array(inner, size)

  def type({:tuple, values}),
    do: raw(["(", Enum.intersperse(Enum.map(values, &render/1), ", "), ")"])

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

  def raw(source), do: %AST.TypeRaw{source: IO.iodata_to_binary(source)}

  def unit, do: %AST.TypeUnit{}
  def option(inner), do: %AST.TypeOption{inner: type(inner)}
  def result(ok, error), do: %AST.TypeResult{ok: type(ok), error: type(error)}
  def nif_result(inner), do: %AST.TypeNifResult{inner: type(inner)}
  def vec(inner), do: %AST.TypeVec{inner: type(inner)}
  def slice(inner), do: %AST.TypeSlice{inner: type(inner)}
  def array(inner, size), do: %AST.TypeArray{inner: type(inner), size: size}

  def ref(inner, opts \\ []),
    do: %AST.TypeRef{inner: type(inner), lifetime: Keyword.get(opts, :lifetime)}

  def mut_ref(inner, opts \\ []),
    do: %AST.TypeRef{inner: type(inner), mutable: true, lifetime: Keyword.get(opts, :lifetime)}

  def term(lifetime \\ :a), do: %AST.TypePath{parts: [:Term], lifetimes: List.wrap(lifetime)}

  defp render(value) do
    value
    |> type()
    |> Render.render_type()
    |> IO.iodata_to_binary()
  end
end
