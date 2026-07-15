defmodule RustQZeroRustConsumer.Native do
  @moduledoc false

  use RustQ.Native, crates: [crc32fast: "1"]

  alias RustQ.Type, as: R

  @type point :: %{
          required(:x) => float(),
          required(:y) => float()
        }

  @type mode :: :fast | :safe

  @spec add(integer(), integer()) :: integer()
  defnif(add(left, right), do: add_impl(left, right))

  @spec add_impl(integer(), integer()) :: integer()
  defrustp(add_impl(left, right), do: left + right)

  @spec sum([float()]) :: float()
  defnif(sum(values), do: Enum.sum(values))

  @spec factorial(integer()) :: integer()
  defnif(factorial(0), do: 1)
  defnif(factorial(value), do: value * factorial(value - 1))

  @spec positives([integer()]) :: [integer()]
  defnif(positives(values), do: Enum.filter(values, fn value -> value > 0 end))

  @spec total([integer()]) :: integer()
  defnif(total(values), do: Enum.reduce(values, 0, fn value, total -> value + total end))

  @spec translate(point(), float(), float()) :: point()
  defnif translate(point, dx, dy) do
    %{x: point.x + dx, y: point.y + dy}
  end

  @spec invert_mode(mode()) :: mode()
  defnif invert_mode(mode) do
    case mode do
      :fast -> enum_variant(Mode, :safe)
      :safe -> enum_variant(Mode, :fast)
    end
  end

  @spec checksum(String.t()) :: R.u32()
  defnif(checksum(value), do: Crc32fast.hash(value.as_bytes()))

  @spec byte_count(binary()) :: integer()
  defnif(byte_count(value), do: cast(value.len(), R.i64()))
end
