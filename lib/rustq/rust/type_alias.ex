defmodule RustQ.Rust.TypeAlias do
  @moduledoc """
  Represents a Rust type alias built with `RustQ.Rust.type_alias/3`.
  """
  defstruct [:name, :type, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end
