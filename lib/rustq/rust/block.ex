defmodule RustQ.Rust.Block do
  @moduledoc false

  defstruct lines: []

  @type t :: %__MODULE__{lines: [term()]}
end
