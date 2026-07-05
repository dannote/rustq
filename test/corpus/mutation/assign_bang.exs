defmodule RustQ.Corpus.Mutation.AssignBang do
  @moduledoc "assign! marks local bindings mutable."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec bump(R.u32()) :: R.u32()
  defrust bump(value) do
    current = value
    assign!(current, current + 1)
    current
  end
end
