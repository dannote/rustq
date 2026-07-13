defmodule RustQ.Rust.Fragment do
  @moduledoc """
  Explicit Rust source fragment used at template splice boundaries.

  Prefer `RustQ.Rust.AST` nodes for generated structure. A fragment is the
  deliberate escape hatch for syntax RustQ does not yet model structurally.
  """

  @enforce_keys [:kind, :source]
  defstruct [:kind, :source]

  @type kind :: :raw | :item | :impl_item | :field | :stmt | :arg | :arm | :expr | :type
  @type t :: %__MODULE__{kind: kind(), source: iodata()}
end
