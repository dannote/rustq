defmodule RustQZeroRustConsumer.Point do
  @type t :: %__MODULE__{x: float(), y: float()}
  defstruct [:x, :y]
end

defmodule RustQZeroRustConsumer.Circle do
  @moduledoc false
  defstruct [:radius]
end

defmodule RustQZeroRustConsumer.Rectangle do
  @moduledoc false
  defstruct [:width, :height]
end

defmodule RustQZeroRustConsumer.NativeError do
  @moduledoc false
  defexception [:message]
end

defmodule RustQZeroRustConsumer.Native do
  @moduledoc false

  use RustQ.Native, crates: [crc32fast: "1"]

  alias RustQ.Type, as: R

  @type coordinates :: %{
          required(:x) => float(),
          required(:y) => float()
        }

  @type counter_state :: %{required(:value) => integer()}
  @type counter :: R.resource(counter_state())
  @type mode :: :fast | :safe

  @type circle :: %RustQZeroRustConsumer.Circle{radius: float()}

  @type rectangle :: %RustQZeroRustConsumer.Rectangle{
          width: float(),
          height: float()
        }

  @type shape :: circle() | rectangle()

  @type native_error :: %RustQZeroRustConsumer.NativeError{
          message: String.t(),
          __exception__: boolean()
        }

  @type structured_point :: %RustQZeroRustConsumer.Point{
          x: float(),
          y: float()
        }

  @spec add(integer(), integer()) :: integer()
  defnif(add(left, right), do: add_impl(left, right))

  @spec add_impl(integer(), integer()) :: integer()
  defrustp(add_impl(left, right), do: left + right)

  @spec sum([float()]) :: float()
  defnif(sum(values), do: Enum.sum(values))

  @spec factorial(integer()) :: integer()
  defnif(factorial(0), do: 1)
  defnif(factorial(value), do: value * factorial(value - 1))

  @spec recursive_sum([integer()]) :: integer()
  defnif(recursive_sum([]), do: 0)
  defnif(recursive_sum([head | tail]), do: head + recursive_sum(tail))

  @spec squares([integer()]) :: [integer()]
  defnif(squares(values), do: for(value <- values, do: value * value))

  @spec positives([integer()]) :: [integer()]
  defnif(positives(values), do: Enum.filter(values, fn value -> value > 0 end))

  @spec total([integer()]) :: integer()
  defnif(total(values), do: Enum.reduce(values, 0, fn value, total -> value + total end))

  @spec translate(coordinates(), float(), float()) :: coordinates()
  defnif translate(point, dx, dy) do
    %{x: point.x + dx, y: point.y + dy}
  end

  @spec coordinate_sum(coordinates()) :: float()
  defnif coordinate_sum(coordinates) do
    case coordinates do
      %{x: x, y: y} -> x + y
    end
  end

  @spec invert_mode(mode()) :: mode()
  defnif invert_mode(mode) do
    case mode do
      :fast -> enum_variant(Mode, :safe)
      :safe -> enum_variant(Mode, :fast)
    end
  end

  @spec scale_point(structured_point(), float()) :: structured_point()
  defnif scale_point(point, factor) do
    %RustQZeroRustConsumer.Point{x: point.x * factor, y: point.y * factor}
  end

  @spec shape_area(shape()) :: float()
  defnif(shape_area(%RustQZeroRustConsumer.Circle{radius: radius}), do: radius * radius)

  defnif(shape_area(%RustQZeroRustConsumer.Rectangle{width: width, height: height}),
    do: width * height
  )

  @spec echo_shape(shape()) :: shape()
  defnif(echo_shape(shape), do: shape)

  @spec echo_error(native_error()) :: native_error()
  defnif(echo_error(error), do: error)

  @spec new_counter(integer()) :: counter()
  defnif(new_counter(value), do: %{value: value})

  @spec counter_value(counter()) :: integer()
  defnif(counter_value(counter), do: counter.value)

  @spec maybe_increment(integer() | nil) :: integer() | nil
  defnif(maybe_increment(nil), do: nil)
  defnif(maybe_increment(value), do: value + 1)

  @spec safe_div(integer(), integer()) :: {:ok, integer()} | {:error, String.t()}
  defnif safe_div(value, divisor) do
    if divisor == 0 do
      {:error, "division by zero"}
    else
      {:ok, div(value, divisor)}
    end
  end

  @spec checksum(String.t()) :: R.u32()
  defnif(checksum(value), do: Crc32fast.hash(value.as_bytes()))

  @spec byte_count(binary()) :: integer()
  defnif(byte_count(value), do: cast(value.len(), R.i64()))

  @spec within_byte(integer()) :: boolean()
  defnif(within_byte(value), do: value in 0..255)

  @spec includes([integer()], integer()) :: boolean()
  defnif(includes(values, value), do: value in values)
end
