defmodule RustQ.Corpus.Propagation.CaseArmAutoBorrow do
  @moduledoc "Expected call argument typing auto-borrows case arms."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
  defrust(use_color(_color), do: :ok)

  @spec run(R.raw(:Color), R.u32()) :: R.nif_result(R.unit())
  defrust run(color, flag) do
    use_color(
      case flag do
        0 -> color
        1 -> color
      end
    )

    :ok
  end
end
