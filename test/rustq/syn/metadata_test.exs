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
               source_line: 2,
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

    assert [
             %RustQ.Syn.Function{
               name: "lerp",
               source_line: 14,
               signature: "fn lerp (a : f32 , b : f32) -> f32",
               signature_ast: lerp_signature,
               args: args,
               returns: "f32"
             }
           ] =
             RustQ.Syn.functions(file)

    assert RustQ.Syn.Signature.render(lerp_signature) == "fn lerp(a: f32, b: f32) -> f32"

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
                   source_line: 20,
                   signature: "fn offset (& mut self , dx : f32 , dy : f32) -> Self",
                   signature_ast: offset_signature,
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

    assert RustQ.Syn.Signature.render(offset_signature) ==
             "fn offset(&mut self, dx: f32, dy: f32) -> Self"
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

  test "returns rustler atom references from parsed Rust source" do
    source = """
    fn decode(value: rustler::Atom) -> bool {
        value == atoms::ok() || value == atoms::error()
    }
    """

    assert RustQ.Syn.atom_references!(source) == ["error", "ok"]
  end

  test "returns receiver method references from parsed Rust source" do
    source = """
    fn draw(canvas: &Canvas, paint: &Paint) {
        canvas.save();
        canvas.draw_rect(Rect::default(), paint);
    }
    """

    assert RustQ.Syn.method_references!(source) == ["draw_rect", "save"]
  end

  test "returns receiver-aware method calls from parsed Rust source" do
    source = """
    fn draw(canvas: &Canvas, state: &mut State, paint: &Paint) {
        canvas.draw_rect(Rect::default(), paint);
        state.canvas().clip_path(path, ClipOp::Intersect, true);
    }
    """

    assert RustQ.Syn.method_calls!(source) == [
             %RustQ.Syn.MethodCall{receiver: "canvas", method: "draw_rect"},
             %RustQ.Syn.MethodCall{receiver: "state", method: "canvas"},
             %RustQ.Syn.MethodCall{receiver: "state . canvas ()", method: "clip_path"}
           ]
  end
end
