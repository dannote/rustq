defmodule RustQZeroRustConsumer.NativeTest do
  use ExUnit.Case, async: true

  test "invokes a NIF generated entirely from Elixir" do
    assert RustQZeroRustConsumer.Native.add(20, 22) == 42
    assert RustQZeroRustConsumer.Native.sum([1.5, 2.0, 3.5]) == 7.0
    assert RustQZeroRustConsumer.Native.factorial(6) == 720
    assert RustQZeroRustConsumer.Native.recursive_sum([1, 2, 3, 4]) == 10
    assert RustQZeroRustConsumer.Native.recursive_sum([]) == 0
    assert RustQZeroRustConsumer.Native.squares([2, 3, 4]) == [4, 9, 16]
    assert RustQZeroRustConsumer.Native.positives([-2, 0, 3, 5]) == [3, 5]
    assert RustQZeroRustConsumer.Native.total([10, 20, 12]) == 42

    assert RustQZeroRustConsumer.Native.translate(%{x: 1.5, y: 2.0}, 3.0, -1.0) == %{
             x: 4.5,
             y: 1.0
           }

    assert RustQZeroRustConsumer.Native.coordinate_sum(%{x: 10.5, y: 2.0}) == 12.5

    assert RustQZeroRustConsumer.Native.invert_mode(:fast) == :safe
    assert RustQZeroRustConsumer.Native.invert_mode(:safe) == :fast

    assert RustQZeroRustConsumer.Native.scale_point(
             %RustQZeroRustConsumer.Point{x: 2.0, y: 3.0},
             2.5
           ) == %RustQZeroRustConsumer.Point{x: 5.0, y: 7.5}

    circle = %RustQZeroRustConsumer.Circle{radius: 2.0}
    rectangle = %RustQZeroRustConsumer.Rectangle{width: 4.0, height: 3.0}
    assert RustQZeroRustConsumer.Native.shape_area(circle) == 4.0
    assert RustQZeroRustConsumer.Native.shape_area(rectangle) == 12.0
    assert RustQZeroRustConsumer.Native.echo_shape(circle) == circle
    assert RustQZeroRustConsumer.Native.echo_shape(rectangle) == rectangle

    error = %RustQZeroRustConsumer.NativeError{message: "native failure"}
    assert RustQZeroRustConsumer.Native.echo_error(error) == error

    counter = RustQZeroRustConsumer.Native.new_counter(42)
    assert is_reference(counter)
    assert RustQZeroRustConsumer.Native.counter_value(counter) == 42

    assert RustQZeroRustConsumer.Native.maybe_increment(nil) == nil
    assert RustQZeroRustConsumer.Native.maybe_increment(41) == 42
    assert RustQZeroRustConsumer.Native.safe_div(42, 6) == {:ok, 7}
    assert RustQZeroRustConsumer.Native.safe_div(42, 0) == {:error, "division by zero"}

    assert RustQZeroRustConsumer.Native.checksum("123456789") == 0xCBF43926
    assert RustQZeroRustConsumer.Native.byte_count(<<0, 1, 2, 3>>) == 4
    assert RustQZeroRustConsumer.Native.within_byte(255)
    refute RustQZeroRustConsumer.Native.within_byte(256)
    assert RustQZeroRustConsumer.Native.includes([1, 3, 5], 3)
    refute RustQZeroRustConsumer.Native.includes([1, 3, 5], 4)

    assert RustQZeroRustConsumer.Native.integer_abs(-42) == 42
    assert RustQZeroRustConsumer.Native.integer_min(7, 3) == 3
    assert RustQZeroRustConsumer.Native.byte_size_of("hé") == 3
    assert RustQZeroRustConsumer.Native.list_length([1, 2, 3]) == 3
    assert RustQZeroRustConsumer.Native.coordinate_size(%{x: 1.0, y: 2.0}) == 2
    assert RustQZeroRustConsumer.Native.pair_first({10, 20}) == 10
    assert RustQZeroRustConsumer.Native.pair_replace({10, 20}, 30) == {10, 30}
    assert RustQZeroRustConsumer.Native.pair_size({10, 20}) == 2

    assert RustQZeroRustConsumer.Native.count_values([1, 2, 3]) == 3
    assert RustQZeroRustConsumer.Native.count_positive([-1, 0, 2, 3]) == 2
    assert RustQZeroRustConsumer.Native.values_empty([])
    refute RustQZeroRustConsumer.Native.values_empty([1])
    assert RustQZeroRustConsumer.Native.find_positive([-2, 0, 3, 4]) == 3
    assert RustQZeroRustConsumer.Native.find_positive([-2, 0]) == nil
    assert RustQZeroRustConsumer.Native.concat_values([[1, 2], [], [3]]) == [1, 2, 3]
    assert RustQZeroRustConsumer.Native.zip_values([1, 2], [3, 4, 5]) == [{1, 3}, {2, 4}]
    assert RustQZeroRustConsumer.Native.unzip_values([{1, 3}, {2, 4}]) == {[1, 2], [3, 4]}
    assert RustQZeroRustConsumer.Native.reverse_values([1, 2, 3]) == [3, 2, 1]
    assert RustQZeroRustConsumer.Native.sort_values([3, 1, 2]) == [1, 2, 3]
    assert RustQZeroRustConsumer.Native.take_two([1, 2, 3]) == [1, 2]
    assert RustQZeroRustConsumer.Native.drop_one([1, 2, 3]) == [2, 3]

    assert RustQZeroRustConsumer.Native.first_value([5, 6]) == 5
    assert RustQZeroRustConsumer.Native.first_value([]) == nil
    assert RustQZeroRustConsumer.Native.last_value([5, 6]) == 6
    assert RustQZeroRustConsumer.Native.flatten_values([[[1], [2, 3]], [[]]]) == [1, 2, 3]
    assert RustQZeroRustConsumer.Native.first_or([], 9) == 9
    assert RustQZeroRustConsumer.Native.first_or([5], 9) == 5
    assert RustQZeroRustConsumer.Native.wrap_value(7) == [7]
    assert RustQZeroRustConsumer.Native.duplicate_value(4) == [4, 4, 4]

    assert RustQZeroRustConsumer.Native.coordinate_x(%{x: 1.5, y: 2.5}) == 1.5
    assert RustQZeroRustConsumer.Native.coordinate_get_x(%{x: 1.5, y: 2.5}) == 1.5
    assert RustQZeroRustConsumer.Native.coordinate_get_missing(%{x: 1.5, y: 2.5}, 9) == 9
    assert RustQZeroRustConsumer.Native.coordinate_has_x(%{x: 1.5, y: 2.5})

    assert RustQZeroRustConsumer.Native.coordinate_put_x(%{x: 1.5, y: 2.5}, 8.0) == %{
             x: 8.0,
             y: 2.5
           }

    assert RustQZeroRustConsumer.Native.starts_with("rustq", "rust")
    assert RustQZeroRustConsumer.Native.ends_with("rustq", "stq")
    assert RustQZeroRustConsumer.Native.string_contains("rustq", "us")
    assert RustQZeroRustConsumer.Native.trim_string("  rustq \n") == "rustq"
    assert RustQZeroRustConsumer.Native.replace_string("a-b-a", "a", "x") == "x-b-x"
    assert RustQZeroRustConsumer.Native.duplicate_string("rq") == "rqrqrq"
    assert RustQZeroRustConsumer.Native.valid_utf8("rustq")
    refute RustQZeroRustConsumer.Native.valid_utf8(<<255>>)
    assert RustQZeroRustConsumer.Native.tuple_to_list({1, 2, 3}) == [1, 2, 3]
  end
end
