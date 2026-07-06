defmodule RustQ.Corpus.Propagation.OptionSomeAutoBorrow do
  @moduledoc "Expected option inner types auto-borrow some/1 values."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec use_color_option(R.option(R.ref(R.raw(:Color)))) :: R.nif_result(R.unit())
  defrust(use_color_option(_color), do: :ok)

  @spec use_tuple_option(R.option({R.ref(R.raw(:Color)), R.i64()})) :: R.nif_result(R.unit())
  defrust(use_tuple_option(_tuple), do: :ok)

  @spec run(R.raw(:Color)) :: R.nif_result(R.unit())
  defrust run(color) do
    use_color_option(some(color))
    use_tuple_option(some({color, 1}))

    :ok
  end
end
