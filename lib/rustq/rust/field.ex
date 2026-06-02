defmodule RustQ.Rust.Field do
  @moduledoc """
  Represents a Rust struct field built with `RustQ.Rust.field/3`.
  """
  defstruct [:name, :type, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end
