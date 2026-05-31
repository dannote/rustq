defmodule RustQ.ParserTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "parse validates templates" do
    assert {:ok, %RustQ.Template{filename: "ok.rs"}} = RustQ.parse("fn ok() {}", "ok.rs")
    assert RustQ.valid?("fn ok() {}", "ok.rs")

    assert {:error, [error]} = RustQ.parse("fn broken(", "broken.rs")
    refute RustQ.valid?("fn broken(", "broken.rs")
    assert error.type == :invalid_template
    assert error.context == :template
    assert error.filename == "broken.rs"
  end

  test "parses fragments" do
    assert {:ok, %RustQ.Rust.Fragment{kind: :field}} = RustQ.parse_fragment(:field, "pub id: i64")
    assert RustQ.valid_fragment?(:arm, Rust.arm("Some(value)", "value"))
    refute RustQ.valid_fragment?(:stmt, "let =")

    assert {:error, [%{type: :invalid_splice, context: :stmt}]} =
             RustQ.parse_fragment(:stmt, "let =")
  end
end
