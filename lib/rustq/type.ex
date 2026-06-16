defmodule RustQ.Type do
  @moduledoc """
  Typespec vocabulary for `RustQ.Meta.defrust/2`.

  These functions exist so Rust-oriented types can be written in ordinary Elixir
  `@spec` and `@type` declarations. `RustQ.Meta` reads their quoted AST during
  compilation; the functions are not meant to be called at runtime.
  """

  def atom, do: type_only!()
  def bool, do: type_only!()
  def f32, do: type_only!()
  def f64, do: type_only!()
  def i64, do: type_only!()
  def term, do: type_only!()
  def u8, do: type_only!()
  def u32, do: type_only!()
  def unit, do: type_only!()

  def ref(_type), do: type_only!()
  def mut_ref(_type), do: type_only!()
  def option(_type), do: type_only!()
  def vec(_type), do: type_only!()
  def result(_ok, _error), do: type_only!()
  def nif_result(_type), do: type_only!()

  defp type_only! do
    raise "RustQ.Type functions are typespec markers for RustQ.Meta; they are not runtime functions"
  end
end
