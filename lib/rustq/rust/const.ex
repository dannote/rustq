defmodule RustQ.Rust.Const do
  @moduledoc false
  defstruct [:name, :type, :value, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          value: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end
