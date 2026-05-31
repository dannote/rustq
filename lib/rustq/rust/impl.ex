defmodule RustQ.Rust.Impl do
  @moduledoc false
  defstruct [:target, items: [], trait: nil]

  @type t :: %__MODULE__{target: term(), items: [term()], trait: term() | nil}
end
