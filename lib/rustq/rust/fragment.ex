defmodule RustQ.Rust.Fragment do
  @moduledoc false
  defstruct [:kind, :code]

  @type t :: %__MODULE__{kind: atom(), code: iodata()}
end
