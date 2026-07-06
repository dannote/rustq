defmodule RustQ.Corpus.Propagation.DownstreamVecSliceAutoBorrow do
  @moduledoc "Infer Vec binding type from downstream slice use and auto-borrow it."

  use RustQ.Meta

  alias RustQ.Type, as: R

  defrustmod(Vec, as: :Vec)

  @spec use_bytes(R.slice(R.u8())) :: R.nif_result(R.unit())
  defrust use_bytes(_bytes) do
    :ok
  end

  @spec run() :: R.nif_result(R.unit())
  defrust run() do
    bytes = Vec.new()
    use_bytes(bytes)
  end
end
