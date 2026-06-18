defmodule RustQ.SynTest do
  use ExUnit.Case, async: true

  test "parses top-level Rust metadata" do
    source = """
    pub enum SkPathOp {
        Difference = 0,
        Intersect = 1,
        Union = 2,
    }

    pub struct Point {
        pub x: f32,
        pub y: f32,
    }

    pub fn lerp(a: f32, b: f32) -> f32 {
        a + b
    }
    """

    assert {:ok, file} = RustQ.Syn.parse(source)

    assert [
             %RustQ.Syn.Enum{
               name: "SkPathOp",
               visibility: :public,
               variants: ["Difference", "Intersect", "Union"]
             }
           ] = RustQ.Syn.enums(file)

    assert [%RustQ.Syn.Struct{name: "Point", fields: fields}] = RustQ.Syn.structs(file)

    assert [%RustQ.Syn.Field{name: "x", type: "f32"}, %RustQ.Syn.Field{name: "y", type: "f32"}] =
             fields

    assert [%RustQ.Syn.Function{name: "lerp", args: args, returns: "f32"}] =
             RustQ.Syn.functions(file)

    assert [%RustQ.Syn.Arg{name: "a", type: "f32"}, %RustQ.Syn.Arg{name: "b", type: "f32"}] =
             args
  end

  test "returns variants for a named enum" do
    source = """
    enum Hidden { A, B }
    pub enum Shown { One, Two }
    """

    assert {:ok, ["One", "Two"]} = RustQ.Syn.enum_variants(source, "Shown")
    assert {:error, "enum Missing not found"} = RustQ.Syn.enum_variants(source, "Missing")
  end
end
