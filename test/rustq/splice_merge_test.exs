defmodule RustQ.SpliceMergeTest do
  use ExUnit.Case, async: true

  test "merges nested splice sources by concatenating duplicate names" do
    splices =
      RustQ.Splice.merge([
        [items: "pub fn one() {}"],
        %{items: "pub fn two() {}", more: "pub fn three() {}"},
        [items: ["pub fn four() {}"]]
      ])

    assert splices[:items] == ["pub fn one() {}", "pub fn two() {}", "pub fn four() {}"]
    assert splices[:more] == ["pub fn three() {}"]
  end

  test "template splice accepts nested splice sources" do
    splices = [
      [items: "pub fn one() -> i32 { 1 }"],
      [items: "pub fn two() -> i32 { 2 }"]
    ]

    code =
      "mod generated { __rq_items!(); }"
      |> RustQ.parse!("generated.rs")
      |> RustQ.splice(splices)
      |> RustQ.render!()

    assert code =~ "pub fn one() -> i32"
    assert code =~ "pub fn two() -> i32"
  end
end
