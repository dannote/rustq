defmodule RustQ.Rust.Use do
  @moduledoc false
  defstruct [:path, vis: nil]

  @type t :: %__MODULE__{path: term(), vis: atom() | String.t() | nil}
end
