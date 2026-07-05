defmodule RustQ.Corpus.Propagation.IfBranchAutoBorrow do
  @moduledoc "Expected call argument typing auto-borrows if branches."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
  defrust(use_color(_color), do: :ok)

  @spec run(R.raw(:Color), R.bool()) :: R.nif_result(R.unit())
  defrust run(color, flag) do
    use_color(
      if flag do
        color
      else
        color
      end
    )

    :ok
  end
end
