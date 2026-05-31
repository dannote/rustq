defmodule RustQ.Template do
  @moduledoc """
  Parsed Rust template plus pending substitutions.
  """

  defstruct [:source, :filename, bindings: [], splices: []]

  @type t :: %__MODULE__{
          source: String.t(),
          filename: String.t(),
          bindings: keyword(),
          splices: [{atom(), term()}]
        }
end
