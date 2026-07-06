defmodule RustQ.Corpus.Propagation.RemoteVecSliceAutoBorrow do
  @moduledoc "Infer Vec binding type from downstream remote slice use and auto-borrow it."

  use RustQ.Meta, rust_sources: ["test/fixtures/data_new_copy.rs"]

  alias RustQ.Type, as: R

  defrustmod(Vec, as: :Vec)

  @spec run() :: R.nif_result(R.path(:Data))
  defrust run() do
    bytes = Vec.new()
    {:ok, Data.new_copy(bytes)}
  end
end
