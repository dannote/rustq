defmodule RustQ.Rust.ModDecl do
  @moduledoc false
  defstruct [:name, attrs: [], items: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          items: [term()],
          vis: atom() | String.t() | nil
        }
end
