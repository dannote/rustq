defmodule RustQ.ErrorTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "returns structured splice errors" do
    assert {:error, [error]} =
             RustQ.render("__rq_items!();", "broken.rs", splice: [items: ["pub mod ;"]])

    assert error.type == :invalid_splice
    assert error.context == :item
    assert error.name == :items
    assert error.fragment == "pub mod ;"
    assert error.filename == "broken.rs"
    assert is_binary(error.message)
  end

  test "returns structured binding errors" do
    assert {:error, [error]} =
             RustQ.render("fn value() -> i32 { __rq_value!() }", "broken.rs",
               bind: [value: Rust.expr("+")]
             )

    assert error.type == :invalid_binding
    assert error.context == :expr_binding
    assert error.name == :value
    assert error.fragment == "+"
    assert error.filename == "broken.rs"
    assert is_binary(error.message)
  end
end
