defmodule RustQ.Corpus.Expr.Pipeline do
  @moduledoc "Pipeline lowering into nested calls."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec add_one(R.u32()) :: R.u32()
  defrust add_one(value) do
    value + 1
  end

  @spec double(R.u32()) :: R.u32()
  defrust double(value) do
    value * 2
  end

  @spec run(R.u32()) :: R.u32()
  defrust run(value) do
    value
    |> add_one()
    |> double()
  end
end
