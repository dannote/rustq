defmodule RustQ.TestFixture do
  use RustQ.Meta

  @spec increment(integer()) :: integer()
  defrustp(increment(value), do: value + 1)

  @spec guarded_sign(integer()) :: integer()
  defnif(guarded_sign(value) when value > 0, do: 1)
  defnif(guarded_sign(_value), do: 0)
end

defmodule RustQ.TestTest do
  use RustQ.Test, async: true

  test "asserts focused defrust output" do
    assert_defrust(RustQ.TestFixture, :increment, "fn increment(value: i64) -> i64")
    assert_defrust(RustQ.TestFixture, :guarded_sign, ~r/value if value > 0/)
    assert_rust(RustQ.TestFixture, "#[rustler::nif]")
    assert_rust_valid(RustQ.TestFixture)
  end

  test "asserts defnif exports and attributes" do
    assert_defnif(RustQ.TestFixture, :guarded_sign, 1, "fn guarded_sign(arg1: i64) -> i64")
    assert RustQ.Test.nif?(RustQ.TestFixture, :guarded_sign)
  end

  test "raises focused errors for modules without RustQ metadata" do
    assert_raise ArgumentError, ~r/does not expose __rustq_source__/, fn ->
      RustQ.Test.source!(__MODULE__)
    end
  end
end
