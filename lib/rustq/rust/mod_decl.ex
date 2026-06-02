defmodule RustQ.Rust.ModDecl do
  @moduledoc """
  Represents a Rust module declaration built with `RustQ.Rust.mod/2`.
  """
  defstruct [:name, attrs: [], items: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          items: [term()],
          vis: atom() | String.t() | nil
        }
end
