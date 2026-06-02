defmodule RustQ.Rust.Impl do
  @moduledoc """
  Represents a Rust `impl` block built with `RustQ.Rust.impl/2`.
  """
  defstruct [:target, items: [], trait: nil]

  @type t :: %__MODULE__{target: term(), items: [term()], trait: term() | nil}
end
