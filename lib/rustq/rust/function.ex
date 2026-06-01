defmodule RustQ.Rust.Function do
  @moduledoc false
  defstruct [
    :name,
    args: [],
    attrs: [],
    body: "",
    returns: nil,
    vis: nil,
    generics: [],
    where: []
  ]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          args: [term()],
          attrs: [term()],
          body: iodata(),
          returns: term(),
          vis: atom() | String.t() | nil,
          generics: [term()],
          where: [term()]
        }
end
