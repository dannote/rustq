defmodule RustQ.Corpus.Collections.MapClosures do
  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec increment(R.u32()) :: R.u32()
  defrust(increment(value), do: value + 1)

  @spec map_named(R.vec(R.u32())) :: R.vec(R.u32())
  defrust map_named(values) do
    Enum.map(values, &increment/1)
  end

  @spec map_block(R.vec(R.u32())) :: R.vec(R.u32())
  defrust map_block(values) do
    Enum.map(values, fn value ->
      doubled = value * 2
      doubled + 1
    end)
  end
end
