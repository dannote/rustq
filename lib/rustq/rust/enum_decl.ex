defmodule RustQ.Rust.EnumDecl do
  @moduledoc false
  defstruct [:name, attrs: [], variants: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          variants: [term()],
          vis: atom() | String.t() | nil
        }
end
