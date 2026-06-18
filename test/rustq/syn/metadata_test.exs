defmodule RustQ.Syn.MetadataTest do
  use ExUnit.Case, async: true

  test "parses top-level Rust metadata" do
    source = """
    /// Path operation docs.
    pub enum SkPathOp {
        Difference = 0,
        Intersect = 1,
        Union = 2,
    }

    /// Point docs.
    pub struct Point {
        pub x: f32,
        pub y: f32,
    }

    pub fn lerp(a: f32, b: f32) -> f32 {
        a + b
    }

    impl Point {
        /// Offset docs.
        pub fn offset(&mut self, dx: f32, dy: f32) -> Self {
            Self { x: self.x + dx, y: self.y + dy }
        }
    }
    """

    assert {:ok, file} = RustQ.Syn.parse(source)

    assert [
             %RustQ.Syn.Enum{
               name: "SkPathOp",
               visibility: :public,
               docs: ["Path operation docs."],
               variants: ["Difference", "Intersect", "Union"]
             }
           ] = RustQ.Syn.enums(file)

    assert [%RustQ.Syn.Struct{name: "Point", docs: ["Point docs."], fields: fields}] =
             RustQ.Syn.structs(file)

    assert [
             %RustQ.Syn.Field{
               name: "x",
               type: "f32",
               type_ast: %RustQ.Syn.Type.Path{name: "f32"}
             },
             %RustQ.Syn.Field{name: "y", type: "f32", type_ast: %RustQ.Syn.Type.Path{name: "f32"}}
           ] = fields

    assert [%RustQ.Syn.Function{name: "lerp", args: args, returns: "f32"}] =
             RustQ.Syn.functions(file)

    assert [
             %RustQ.Syn.Arg{name: "a", type: "f32", type_ast: %RustQ.Syn.Type.Path{name: "f32"}},
             %RustQ.Syn.Arg{name: "b", type: "f32", type_ast: %RustQ.Syn.Type.Path{name: "f32"}}
           ] = args

    assert [
             %RustQ.Syn.Impl{
               target: "Point",
               target_ast: %RustQ.Syn.Type.Path{name: "Point"},
               trait: nil,
               methods: [
                 %RustQ.Syn.Method{
                   name: "offset",
                   visibility: :public,
                   docs: ["Offset docs."],
                   args: method_args,
                   returns: "Self",
                   returns_ast: %RustQ.Syn.Type.Self{code: "Self"}
                 }
               ]
             }
           ] = RustQ.Syn.impls(file)

    assert [
             %RustQ.Syn.Arg{
               name: "self",
               type: "& mut self",
               type_ast: %RustQ.Syn.Type.Ref{mutable: true, inner: %RustQ.Syn.Type.Self{}}
             },
             %RustQ.Syn.Arg{name: "dx", type: "f32", type_ast: %RustQ.Syn.Type.Path{name: "f32"}},
             %RustQ.Syn.Arg{name: "dy", type: "f32", type_ast: %RustQ.Syn.Type.Path{name: "f32"}}
           ] = method_args
  end

  test "parses common compound type metadata" do
    source = """
    impl Canvas {
        pub fn draw_rect(&self, rect: impl AsRef<Rect>, paint: Option<&Paint>) -> Result<&Self, Error> {
            Ok(self)
        }
    }
    """

    assert [method] = source |> RustQ.Syn.parse!() |> RustQ.Syn.methods()

    assert %RustQ.Syn.Method{
             args: [
               %RustQ.Syn.Arg{type_ast: %RustQ.Syn.Type.Ref{inner: %RustQ.Syn.Type.Self{}}},
               %RustQ.Syn.Arg{
                 type_ast: %RustQ.Syn.Type.ImplTrait{
                   traits: [
                     %RustQ.Syn.Type.Path{
                       name: "AsRef",
                       args: [%RustQ.Syn.Type.Path{name: "Rect"}]
                     }
                   ]
                 }
               },
               %RustQ.Syn.Arg{
                 type_ast: %RustQ.Syn.Type.Option{
                   inner: %RustQ.Syn.Type.Ref{inner: %RustQ.Syn.Type.Path{name: "Paint"}}
                 }
               }
             ],
             returns_ast: %RustQ.Syn.Type.Result{
               ok: %RustQ.Syn.Type.Ref{inner: %RustQ.Syn.Type.Self{}},
               error: %RustQ.Syn.Type.Path{name: "Error"}
             }
           } = method
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
