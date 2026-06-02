defmodule RustQ.Rust.Struct do
  @moduledoc """
  Represents a Rust struct declaration built with `RustQ.Rust.struct/2`.
  """
  defstruct [:name, attrs: [], fields: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          fields: [term()],
          vis: atom() | String.t() | nil
        }
end
