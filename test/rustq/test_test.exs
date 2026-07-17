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

  test "returns focused generated Rust for ordinary ExUnit assertions" do
    assert rust_source!(RustQ.TestFixture, :increment) =~ "fn increment(value: i64) -> i64"

    assert rust_source!(RustQ.TestFixture, :increment) == """
           fn increment(value: i64) -> i64 {
               value + 1
           }
           """

    assert rust_source!(RustQ.TestFixture, :guarded_sign) =~ ~r/value if value > 0/
    assert rust_source!(RustQ.TestFixture) =~ "#[rustler::nif]"
    assert RustQ.valid?(rust_source!(RustQ.TestFixture), "rustq_test_fixture.rs")
  end

  test "identifies exported NIFs" do
    assert nif_exported?(RustQ.TestFixture, :guarded_sign, 1)
    refute nif_exported?(RustQ.TestFixture, :guarded_sign, 2)
    refute nif_exported?(RustQ.TestFixture, :increment, 1)
    refute nif_exported?(__MODULE__, :module_info, 0)
  end

  test "raises focused errors for modules without RustQ metadata" do
    assert_raise ArgumentError, ~r/does not expose __rustq_source__/, fn ->
      rust_source!(__MODULE__)
    end
  end
end
