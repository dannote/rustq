defmodule RustQ.Rust.Function do
  @moduledoc false
  defstruct [:name, args: [], attrs: [], body: "", returns: nil, vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          args: [term()],
          attrs: [term()],
          body: iodata(),
          returns: term(),
          vis: atom() | String.t() | nil
        }
end
