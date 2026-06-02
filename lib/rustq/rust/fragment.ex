defmodule RustQ.Rust.Fragment do
  @moduledoc """
  Represents a raw Rust fragment validated or spliced by RustQ.
  """
  defstruct [:kind, :code]

  @type t :: %__MODULE__{kind: atom(), code: iodata()}
end
