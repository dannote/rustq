defmodule RustQ.SpliceGroupTest do
  use ExUnit.Case, async: true

  alias RustQ.SpliceGroup

  test "merges duplicate splice names by concatenating replacements" do
    group =
      SpliceGroup.merge([
        [items: "pub fn one() {}"],
        %{items: "pub fn two() {}", more: "pub fn three() {}"},
        SpliceGroup.new(items: ["pub fn four() {}"])
      ])

    splices = SpliceGroup.to_keyword(group)

    assert splices[:items] == ["pub fn one() {}", "pub fn two() {}", "pub fn four() {}"]
    assert splices[:more] == ["pub fn three() {}"]
  end

  test "template splice accepts splice groups" do
    group =
      SpliceGroup.new(items: "pub fn one() -> i32 { 1 }")
      |> SpliceGroup.append(:items, "pub fn two() -> i32 { 2 }")

    code =
      "mod generated { __rq_items!(); }"
      |> RustQ.parse!("generated.rs")
      |> RustQ.splice(group)
      |> RustQ.codegen!()

    assert code =~ "pub fn one() -> i32"
    assert code =~ "pub fn two() -> i32"
  end
end
