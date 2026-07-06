defmodule RustQ.Corpus.Propagation.VecSliceAutoBorrow do
  @moduledoc "Auto-borrow Vec values passed where a slice is expected."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec use_bytes(R.slice(R.u8())) :: R.nif_result(R.unit())
  defrust use_bytes(_bytes) do
    :ok
  end

  @spec run(R.vec(R.u8())) :: R.nif_result(R.unit())
  defrust run(bytes) do
    use_bytes(bytes)
  end
end
