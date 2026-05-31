defmodule RustQ.SpliceTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "splices top-level items" do
    code =
      "__splice_items!();"
      |> RustQ.render!("items.rs", splice: [items: ["pub mod users;", "pub mod posts;"]])

    assert code =~ "pub mod users;"
    assert code =~ "pub mod posts;"
  end

  test "splices statements into blocks" do
    code =
      """
      pub fn run() {
          __splice_body!();
      }
      """
      |> RustQ.render!("statements.rs", splice: [body: ["let x = 1;", "drop(x);"]])

    assert code =~ "let x = 1;"
    assert code =~ "drop(x);"
  end

  test "splices match arms" do
    code =
      """
      pub fn value(input: Option<i32>) -> i32 {
          match input {
              __splice_arms => unreachable!(),
          }
      }
      """
      |> RustQ.render!("arms.rs",
        splice: [
          arms: [
            Rust.arm("Some(value)", "value"),
            Rust.arm("None", "0")
          ]
        ]
      )

    assert code =~ "Some(value) => value"
    assert code =~ "None => 0"
    refute code =~ "unreachable"
  end
end
