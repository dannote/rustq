defmodule RustQPublicConsumer.PublicAPITest do
  use ExUnit.Case, async: true

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
  end
end
