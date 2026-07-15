defmodule RustQZeroRustConsumer.NativeTest do
  use ExUnit.Case, async: true

  test "invokes a NIF generated entirely from Elixir" do
    assert RustQZeroRustConsumer.Native.add(20, 22) == 42
    assert RustQZeroRustConsumer.Native.sum([1.5, 2.0, 3.5]) == 7.0
    assert RustQZeroRustConsumer.Native.factorial(6) == 720
    assert RustQZeroRustConsumer.Native.positives([-2, 0, 3, 5]) == [3, 5]
    assert RustQZeroRustConsumer.Native.total([10, 20, 12]) == 42

    assert RustQZeroRustConsumer.Native.translate(%{x: 1.5, y: 2.0}, 3.0, -1.0) == %{
             x: 4.5,
             y: 1.0
           }

    assert RustQZeroRustConsumer.Native.invert_mode(:fast) == :safe
    assert RustQZeroRustConsumer.Native.invert_mode(:safe) == :fast
    assert RustQZeroRustConsumer.Native.checksum("123456789") == 0xCBF43926
    assert RustQZeroRustConsumer.Native.byte_count(<<0, 1, 2, 3>>) == 4
  end
end
