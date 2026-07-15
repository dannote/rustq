defmodule RustQPublicConsumer.Generated do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec increment(R.u32()) :: R.u32()
  defrust(increment(value), do: value + 1)

  @spec increment_all(R.vec(R.u32())) :: R.vec(R.u32())
  defrust increment_all(values) do
    Enum.map(values, &increment/1)
  end
end
