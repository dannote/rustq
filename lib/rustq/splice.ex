defmodule RustQ.Splice do
  @moduledoc """
  Helpers for composing RustQ splice replacements as plain keyword lists.

  Splices use the same shape accepted by `RustQ.render/3`:

      [items: [RustQ.Rust.fragment(:item, "pub fn generated() {}")]]

  `merge/1` also accepts nested splice sources, so manifests can compose output
  from several generators without wrapper structs.
  """

  @type name :: atom()
  @type replacement :: term() | [term()]
  @type t :: keyword([term()])
  @type source :: t() | map() | [source() | {name(), replacement()}]

  @doc """
  Merges splice sources, concatenating duplicate names.

  Accepts ordinary keywords, maps, or nested lists of splice sources:

      RustQ.Splice.merge([
        BaseGenerator.splices(schema),
        NativeGenerator.splices(schema),
        items: RustQ.Rust.fragment(:item, "pub fn generated() {}")
      ])
  """
  @spec merge(source()) :: t()
  def merge(splices), do: merge_into([], splices)

  @doc """
  Appends replacement fragments to a splice name.
  """
  @spec append(t(), name(), replacement()) :: t()
  def append(splices, name, replacement) when is_list(splices) and is_atom(name) do
    replacement = List.wrap(replacement)
    Keyword.update(splices, name, replacement, &(&1 ++ replacement))
  end

  @doc """
  Replaces all fragments for a splice name.
  """
  @spec put(t(), name(), replacement()) :: t()
  def put(splices, name, replacement) when is_list(splices) and is_atom(name) do
    Keyword.put(splices, name, List.wrap(replacement))
  end

  defp merge_into(acc, splices) when is_map(splices) do
    merge_into(acc, Map.to_list(splices))
  end

  defp merge_into(acc, splices) when is_list(splices) do
    Enum.reduce(splices, acc, fn
      {name, replacement}, acc when is_atom(name) -> append(acc, name, replacement)
      nested, acc -> merge_into(acc, nested)
    end)
  end
end
