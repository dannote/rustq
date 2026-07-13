defmodule RustQ.SigilTest do
  use ExUnit.Case, async: true

  use RustQ.Sigil

  alias RustQ.Rust

  test "supports Rust sigils" do
    code =
      ~R"""
      pub fn answer() -> i32 {
          __rq_value!()
      }
      """
      |> RustQ.render!("sigil.rs", bind: [value: Rust.fragment(:expr, "42")])

    assert code =~ "pub fn answer() -> i32"
    assert code =~ "42"
  end
end
