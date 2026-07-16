defmodule RustQPublicConsumer.PublicAPITest do
  use RustQ.Test, async: true

  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  test "uses documented public APIs" do
    assert %AST.Const{} = constant = A.const(:VALUE, :u32, 7, vis: :pub)
    assert Rust.render(constant) =~ "pub const VALUE: u32 = 7;"
    assert {:ok, _template} = RustQ.parse("fn public_consumer() {}", "consumer.rs")

    assert %AST.Function{name: :increment} =
             MetaAST.function!(RustQPublicConsumer.Generated, :increment)

    assert [_, _] = generated = RustQPublicConsumer.Generated.__rustq_items__()
    assert Rust.render_all(generated) =~ "fn increment_all"

    assert_defrust(RustQPublicConsumer.Generated, :increment, "fn increment(value: u32) -> u32")
    assert_defrust(RustQPublicConsumer.Generated, :increment_all, ~r/into_iter.*map/s)
    assert_rust_valid(RustQPublicConsumer.Generated)
  end

  test "prepares ABI items for an externally built and loaded crate" do
    source = RustQ.Native.source(RustQPublicConsumer.ExternalNative)

    assert source =~ "fn wrap<'a>(__rustq_env: Env<'a>, value: Term<'a>)"
    assert function_exported?(RustQPublicConsumer.ExternalNative, :wrap, 1)
    refute function_exported?(RustQPublicConsumer.ExternalNative, :wrap, 2)
    refute function_exported?(RustQPublicConsumer.ExternalNative, :__rustq_load_nif__, 0)
  end
end
