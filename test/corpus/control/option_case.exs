defmodule RustQ.Corpus.Control.OptionCase do
  @moduledoc "Option pattern lowering through case."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec fallback(R.option(R.u32())) :: R.u32()
  defrust fallback(value) do
    case value do
      nil -> 0
      value -> value
    end
  end
end
