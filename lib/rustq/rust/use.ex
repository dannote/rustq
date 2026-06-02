defmodule RustQ.Rust.Use do
  @moduledoc """
  Represents a Rust `use` declaration built with `RustQ.Rust.use/2`.
  """
  defstruct [:path, vis: nil]

  @type t :: %__MODULE__{path: term(), vis: atom() | String.t() | nil}
end
