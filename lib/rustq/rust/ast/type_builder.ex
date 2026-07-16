defmodule RustQ.Rust.AST.TypeBuilder do
  @moduledoc """
  Constructors and normalization for Rust type AST nodes.

  `type/1` accepts existing type nodes, atom/list Rust paths, raw binary source,
  and structural tuples such as `{:option, type}`, `{:result, ok, error}`,
  `{:vec, type}`, tuple types, references, slices, and arrays. Binary source is
  normalized to `RustQ.Rust.AST.TypeRaw`; prefer `raw/1` when an explicit escape
  makes generator intent clearer.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.Identifier

  def type(%{__struct__: _module} = value) do
    if AST.type_node?(value) do
      value
    else
      raise ArgumentError, "expected RustQ type AST node, got: #{inspect(value)}"
    end
  end

  def type(parts) when is_list(parts), do: path(parts)
  def type(part) when is_atom(part), do: path(part)
  def type(source) when is_binary(source), do: raw(source)
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
  def type({:bare_fn, args, opts}), do: bare_fn(args, opts)

  def type({:tuple, values}), do: tuple(values)

  def path(parts_or_part, opts \\ [])

  def path(parts, opts) when is_list(parts),
    do: %AST.TypePath{
      parts: parts,
      lifetimes:
        opts |> Keyword.get(:lifetimes, []) |> List.wrap() |> Enum.map(&Identifier.atom!/1),
      generics: opts |> Keyword.get(:generics, []) |> Enum.map(&type/1)
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
  def tuple([]), do: raise(ArgumentError, "empty tuple types must use unit/0")
  def tuple(items) when is_list(items), do: %AST.TypeTuple{items: Enum.map(items, &type/1)}

  def bare_fn(args, opts \\ []) when is_list(args) and is_list(opts) do
    %AST.TypeBareFn{
      args: Enum.map(args, &type/1),
      returns: opts |> Keyword.get(:returns) |> then(&if(&1, do: type(&1))),
      lifetimes: Keyword.get(opts, :lifetimes, []),
      unsafe: Keyword.get(opts, :unsafe, false),
      external: Keyword.get(opts, :external, false),
      abi: Keyword.get(opts, :abi),
      variadic: Keyword.get(opts, :variadic, false)
    }
  end

  def ref(inner, opts \\ []),
    do: %AST.TypeRef{inner: type(inner), lifetime: Keyword.get(opts, :lifetime)}

  def mut_ref(inner, opts \\ []),
    do: %AST.TypeRef{inner: type(inner), mutable: true, lifetime: Keyword.get(opts, :lifetime)}

  def term(lifetime \\ :a), do: path(:Term, lifetimes: List.wrap(lifetime))
end
