defmodule RustQ.Corpus.Propagation.OptionCaseBindingAutoBorrow do
  @moduledoc "Option case binding types auto-borrow downstream call arguments."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec maybe_color() :: R.option(R.raw(:Color))
  defrust maybe_color() do
    nil
  end

  @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
  defrust(use_color(_color), do: :ok)

  @spec run() :: R.nif_result(R.unit())
  defrust run() do
    case maybe_color() do
      {:some, color} -> use_color(color)
      :none -> :ok
    end

    :ok
  end

  @spec run_as_ref(R.option(R.raw(:Color))) :: R.nif_result(R.unit())
  defrust run_as_ref(color) do
    case color.as_ref() do
      {:some, color} -> use_color(color)
      :none -> :ok
    end

    :ok
  end
end
