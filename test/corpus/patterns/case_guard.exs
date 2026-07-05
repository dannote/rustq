defmodule RustQ.Corpus.Patterns.CaseGuard do
  @moduledoc "Case guard lowering."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec classify(R.u32()) :: R.u32()
  defrust classify(value) do
    case value do
      value when value == 0 -> 1
      _ -> 2
    end
  end
end
