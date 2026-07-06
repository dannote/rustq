defmodule RustQ.Corpus.Propagation.ArraySliceAutoBorrow do
  @moduledoc "Auto-borrow array literals passed where a slice is expected."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec use_values(R.slice(R.u32())) :: R.nif_result(R.unit())
  defrust(use_values(_values), do: :ok)

  @spec run() :: R.nif_result(R.unit())
  defrust run() do
    use_values(array([1, 2, 3]))
    :ok
  end
end
