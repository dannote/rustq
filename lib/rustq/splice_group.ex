defmodule RustQ.SpliceGroup do
  @moduledoc """
  Composable collection of RustQ splice replacements.

  A splice group keeps replacements grouped by splice name and concatenates
  fragments when groups are merged. It is useful when multiple generators
  contribute to the same Rust template.
  """

  defstruct splices: []

  @type name :: atom()
  @type replacement :: term() | [term()]
  @type t :: %__MODULE__{splices: keyword([term()])}

  @doc """
  Creates a splice group from a keyword list, map, or another group.
  """
  @spec new(keyword() | map() | t()) :: t()
  def new(%__MODULE__{} = group), do: group

  def new(splices) when is_map(splices) do
    splices
    |> Map.to_list()
    |> new()
  end

  def new(splices) when is_list(splices) do
    Enum.reduce(splices, %__MODULE__{}, fn {name, replacement}, group ->
      append(group, name, replacement)
    end)
  end

  @doc """
  Appends replacement fragments to a splice name.
  """
  @spec append(t(), name(), replacement()) :: t()
  def append(%__MODULE__{} = group, name, replacement) when is_atom(name) do
    replacement = List.wrap(replacement)
    splices = Keyword.update(group.splices, name, replacement, &(&1 ++ replacement))
    %{group | splices: splices}
  end

  @doc """
  Replaces all fragments for a splice name.
  """
  @spec put(t(), name(), replacement()) :: t()
  def put(%__MODULE__{} = group, name, replacement) when is_atom(name) do
    %{group | splices: Keyword.put(group.splices, name, List.wrap(replacement))}
  end

  @doc """
  Merges multiple splice groups/keywords/maps, concatenating duplicate names.
  """
  @spec merge([keyword() | map() | t()]) :: t()
  def merge(groups) when is_list(groups) do
    Enum.reduce(groups, %__MODULE__{}, &merge(&2, &1))
  end

  @doc """
  Merges two splice groups/keywords/maps, concatenating duplicate names.
  """
  @spec merge(keyword() | map() | t(), keyword() | map() | t()) :: t()
  def merge(left, right) do
    left = new(left)
    right = new(right)

    Enum.reduce(right.splices, left, fn {name, replacement}, group ->
      append(group, name, replacement)
    end)
  end

  @doc """
  Converts a splice group into the keyword format accepted by `RustQ.render/3`.
  """
  @spec to_keyword(keyword() | map() | t()) :: keyword([term()])
  def to_keyword(splices), do: new(splices).splices
end
