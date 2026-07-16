defmodule RustQ.NativeExternalFixture do
  use RustQ.Native,
    build: false,
    load: false,
    crate: :rustq_native_external_fixture

  alias RustQ.Type, as: R

  @type point :: %{required(:x) => integer(), required(:y) => integer()}

  @spec env_echo(term()) :: R.nif_result(term())
  defnif(env_echo(value), do: external_env_echo(nif_env(), value))

  @spec translate(point(), integer(), integer()) :: point()
  defnif(translate(point, dx, dy), do: %{x: point.x + dx, y: point.y + dy})
end

defmodule RustQ.NativeExternalTest do
  use RustQ.Test, async: true

  alias RustQ.Rust.AST

  test "prepares native items without owning the crate build or loader" do
    items = RustQ.Native.items(RustQ.NativeExternalFixture)
    source = RustQ.Native.source(RustQ.NativeExternalFixture)

    assert Enum.any?(items, &match?(%AST.Function{name: :env_echo}, &1))
    assert source =~ "rustler::NifMap"
    assert source =~ "fn env_echo<'a>(__rustq_env: Env<'a>, value: Term<'a>)"
    refute source =~ "rustler::init!"
    refute function_exported?(RustQ.NativeExternalFixture, :__rustq_load_nif__, 0)
  end

  test "implicit Rustler Env does not change the public BEAM arity" do
    assert function_exported?(RustQ.NativeExternalFixture, :env_echo, 1)
    refute function_exported?(RustQ.NativeExternalFixture, :env_echo, 2)

    assert_defnif(
      RustQ.NativeExternalFixture,
      :env_echo,
      1,
      "external_env_echo(__rustq_env, value)"
    )
  end
end
