defmodule RustQ.Rust.TypeAlias do
  @moduledoc false
  defstruct [:name, :type, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end
