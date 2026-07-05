defmodule RustQ.Corpus.Expr.Arithmetic do
  @moduledoc "Arithmetic and bitwise helper lowering."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec compute(R.u32(), R.u32()) :: R.u32()
  defrust compute(left, right) do
    bor(band(left + right, 255), 1)
  end
end
