defmodule RustQ.Meta.Pattern do
  @moduledoc """
  Structural helpers for Rusty-Elixir binding and tuple patterns.
  """

  @spec tuple_elements(Macro.t()) :: [Macro.t()] | nil
  def tuple_elements({:{}, _, elements}) when is_list(elements), do: elements

  def tuple_elements(pattern) when is_tuple(pattern) and tuple_size(pattern) != 3,
    do: Tuple.to_list(pattern)

  def tuple_elements(_pattern), do: nil
end
