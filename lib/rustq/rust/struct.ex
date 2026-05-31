defmodule RustQ.Rust.Struct do
  @moduledoc false
  defstruct [:name, attrs: [], fields: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          fields: [term()],
          vis: atom() | String.t() | nil
        }
end
