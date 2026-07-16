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

  @spec integer_abs(integer()) :: integer()
  defnif(integer_abs(value), do: abs(value))

  @spec integer_min(integer(), integer()) :: integer()
  defnif(integer_min(left, right), do: min(left, right))

  @spec byte_size_of(String.t()) :: integer()
  defnif(byte_size_of(value), do: byte_size(value))

  @spec list_length([integer()]) :: integer()
  defnif(list_length(values), do: length(values))

  @spec coordinate_size(coordinates()) :: integer()
  defnif(coordinate_size(point), do: map_size(point))

  @spec pair_first({integer(), integer()}) :: integer()
  defnif(pair_first(pair), do: elem(pair, 0))

  @spec pair_replace({integer(), integer()}, integer()) :: {integer(), integer()}
  defnif(pair_replace(pair, value), do: put_elem(pair, 1, value))

  @spec pair_size({integer(), integer()}) :: integer()
  defnif(pair_size(pair), do: tuple_size(pair))

  @spec count_values([integer()]) :: integer()
  defnif(count_values(values), do: Enum.count(values))

  @spec count_positive([integer()]) :: integer()
  defnif(count_positive(values), do: Enum.count(values, fn value -> value > 0 end))

  @spec values_empty([integer()]) :: boolean()
  defnif(values_empty(values), do: Enum.empty?(values))

  @spec find_positive([integer()]) :: integer() | nil
  defnif(find_positive(values), do: Enum.find(values, fn value -> value > 0 end))

  @spec concat_values([[integer()]]) :: [integer()]
  defnif(concat_values(values), do: Enum.concat(values))

  @spec zip_values([integer()], [integer()]) :: [{integer(), integer()}]
  defnif(zip_values(left, right), do: Enum.zip(left, right))

  @spec unzip_values([{integer(), integer()}]) :: {[integer()], [integer()]}
  defnif(unzip_values(values), do: Enum.unzip(values))

  @spec reverse_values([integer()]) :: [integer()]
  defnif(reverse_values(values), do: Enum.reverse(values))

  @spec sort_values([integer()]) :: [integer()]
  defnif(sort_values(values), do: Enum.sort(values))

  @spec take_two([integer()]) :: [integer()]
  defnif(take_two(values), do: Enum.take(values, 2))

  @spec drop_one([integer()]) :: [integer()]
  defnif(drop_one(values), do: Enum.drop(values, 1))

  @spec first_value([integer()]) :: integer() | nil
  defnif(first_value(values), do: List.first(values))

  @spec last_value([integer()]) :: integer() | nil
  defnif(last_value(values), do: List.last(values))

  @spec flatten_values([[[integer()]]]) :: [integer()]
  defnif(flatten_values(values), do: List.flatten(values))

  @spec first_or([integer()], integer()) :: integer()
  defnif(first_or(values, default), do: List.first(values, default))

  @spec wrap_value(integer()) :: [integer()]
  defnif(wrap_value(value), do: List.wrap(value))

  @spec duplicate_value(integer()) :: [integer()]
  defnif(duplicate_value(value), do: List.duplicate(value, 3))

  @spec coordinate_x(coordinates()) :: float()
  defnif(coordinate_x(point), do: Map.fetch!(point, :x))

  @spec coordinate_get_x(coordinates()) :: float()
  defnif(coordinate_get_x(point), do: Map.get(point, :x))

  @spec coordinate_get_missing(coordinates(), integer()) :: integer()
  defnif(coordinate_get_missing(point, default), do: Map.get(point, :missing, default))

  @spec coordinate_has_x(coordinates()) :: boolean()
  defnif(coordinate_has_x(point), do: Map.has_key?(point, :x))

  @spec coordinate_put_x(coordinates(), float()) :: coordinates()
  defnif(coordinate_put_x(point, x), do: Map.put(point, :x, x))

  @spec starts_with(String.t(), String.t()) :: boolean()
  defnif(starts_with(value, prefix), do: String.starts_with?(value, prefix))

  @spec ends_with(String.t(), String.t()) :: boolean()
  defnif(ends_with(value, suffix), do: String.ends_with?(value, suffix))

  @spec string_contains(String.t(), String.t()) :: boolean()
  defnif(string_contains(value, part), do: String.contains?(value, part))

  @spec trim_string(String.t()) :: String.t()
  defnif(trim_string(value), do: String.trim(value))

  @spec replace_string(String.t(), String.t(), String.t()) :: String.t()
  defnif(replace_string(value, pattern, replacement),
    do: String.replace(value, pattern, replacement)
  )

  @spec duplicate_string(String.t()) :: String.t()
  defnif(duplicate_string(value), do: String.duplicate(value, 3))

  @spec valid_utf8(binary()) :: boolean()
  defnif(valid_utf8(value), do: String.valid?(value))

  @spec tuple_to_list({integer(), integer(), integer()}) :: [integer()]
  defnif(tuple_to_list(tuple), do: Tuple.to_list(tuple))
end
