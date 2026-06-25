defmodule RustQ.Syn.MetadataTest do
  use ExUnit.Case, async: true

  alias RustQ.Syn
  alias RustQ.Syn.Arg
  alias RustQ.Syn.Impl
  alias RustQ.Syn.Method
  alias RustQ.Syn.MethodCall
  alias RustQ.Syn.Signature
  alias RustQ.Syn.Type

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

    assert {:ok, file} = Syn.parse(source)

    assert [
             %Syn.Enum{
               name: "SkPathOp",
               visibility: :public,
               source_line: 2,
               docs: ["Path operation docs."],
               variants: ["Difference", "Intersect", "Union"]
             }
           ] = Syn.enums(file)

    assert [%Syn.Struct{name: "Point", docs: ["Point docs."], fields: fields}] =
             Syn.structs(file)

    assert [
             %Syn.Field{
               name: "x",
               type: "f32",
               type_ast: %Type.Path{name: "f32"}
             },
             %Syn.Field{name: "y", type: "f32", type_ast: %Type.Path{name: "f32"}}
           ] = fields

    assert [
             %Syn.Function{
               name: "lerp",
               source_line: 14,
               signature: "fn lerp (a : f32 , b : f32) -> f32",
               signature_ast: lerp_signature,
               args: args,
               returns: "f32"
             }
           ] =
             Syn.functions(file)

    assert Signature.render(lerp_signature) == "fn lerp(a: f32, b: f32) -> f32"

    assert [
             %Arg{name: "a", type: "f32", type_ast: %Type.Path{name: "f32"}},
             %Arg{name: "b", type: "f32", type_ast: %Type.Path{name: "f32"}}
           ] = args

    assert [
             %Impl{
               target: "Point",
               target_ast: %Type.Path{name: "Point"},
               trait: nil,
               methods: [
                 %Method{
                   name: "offset",
                   visibility: :public,
                   source_line: 20,
                   signature: "fn offset (& mut self , dx : f32 , dy : f32) -> Self",
                   signature_ast: offset_signature,
                   docs: ["Offset docs."],
                   args: method_args,
                   returns: "Self",
                   returns_ast: %Type.Self{code: "Self"}
                 }
               ]
             }
           ] = Syn.impls(file)

    assert [
             %Arg{
               name: "self",
               type: "& mut self",
               type_ast: %Type.Ref{mutable: true, inner: %Type.Self{}}
             },
             %Arg{name: "dx", type: "f32", type_ast: %Type.Path{name: "f32"}},
             %Arg{name: "dy", type: "f32", type_ast: %Type.Path{name: "f32"}}
           ] = method_args

    assert Signature.render(offset_signature) ==
             "fn offset(&mut self, dx: f32, dy: f32) -> Self"
  end

  test "parses path associated type metadata" do
    source = """
    pub fn merge(filters: impl IntoIterator<Item = Option<ImageFilter>>) {}
    """

    assert {:ok, file} = Syn.parse(source)

    assert [
             %Syn.Function{
               args: [
                 %Arg{
                   type_ast: %Type.ImplTrait{
                     traits: [
                       %Type.Path{
                         name: "IntoIterator",
                         assoc: %{"Item" => %Type.Option{inner: %Type.Path{name: "ImageFilter"}}}
                       }
                     ]
                   }
                 }
               ]
             }
           ] = Syn.functions(file)
  end

  test "parses nested module free functions with module paths" do
    source = """
    pub mod color_filters {
        pub fn blend(c: impl Into<Color>, mode: BlendMode) -> Option<ColorFilter> { todo!() }
    }
    """

    assert {:ok, file} = Syn.parse(source)

    assert [
             %Syn.Function{
               name: "blend",
               module_path: ["color_filters"],
               source_line: 2,
               args: [
                 %Arg{name: "c", type_ast: %Type.ImplTrait{}},
                 %Arg{name: "mode", type_ast: %Type.Path{name: "BlendMode"}}
               ],
               returns_ast: %Type.Option{inner: %Type.Path{name: "ColorFilter"}}
             }
           ] = Syn.functions(file)
  end

  test "parses common compound type metadata" do
    source = """
    impl Canvas {
        pub fn draw_rect(&self, rect: impl AsRef<Rect>, paint: Option<&Paint>) -> Result<&Self, Error> {
            Ok(self)
        }
    }
    """

    assert [method] = source |> Syn.parse!() |> Syn.methods()

    assert %Method{
             args: [
               %Arg{type_ast: %Type.Ref{inner: %Type.Self{}}},
               %Arg{
                 type_ast: %Type.ImplTrait{
                   traits: [
                     %Type.Path{
                       name: "AsRef",
                       args: [%Type.Path{name: "Rect"}]
                     }
                   ]
                 }
               },
               %Arg{
                 type_ast: %Type.Option{
                   inner: %Type.Ref{inner: %Type.Path{name: "Paint"}}
                 }
               }
             ],
             returns_ast: %Type.Result{
               ok: %Type.Ref{inner: %Type.Self{}},
               error: %Type.Path{name: "Error"}
             }
           } = method
  end

  test "returns variants for a named enum" do
    source = """
    enum Hidden { A, B }
    pub enum Shown { One, Two }
    """

    assert {:ok, ["One", "Two"]} = Syn.enum_variants(source, "Shown")
    assert {:error, "enum Missing not found"} = Syn.enum_variants(source, "Missing")
  end

  test "returns rustler atom references from parsed Rust source" do
    source = """
    fn decode(value: rustler::Atom) -> bool {
        value == atoms::ok() || value == atoms::error()
    }
    """

    assert Syn.atom_references!(source) == ["error", "ok"]
  end

  test "returns receiver method references from parsed Rust source" do
    source = """
    fn draw(canvas: &Canvas, paint: &Paint) {
        canvas.save();
        canvas.draw_rect(Rect::default(), paint);
    }
    """

    assert Syn.method_references!(source) == ["draw_rect", "save"]
  end

  test "returns receiver-aware method calls from parsed Rust source" do
    source = """
    fn draw(canvas: &Canvas, state: &mut State, paint: &Paint) {
        canvas.draw_rect(Rect::default(), paint);
        state.canvas().clip_path(path, ClipOp::Intersect, true);
    }
    """

    assert Syn.method_calls!(source) == [
             %MethodCall{receiver: "canvas", method: "draw_rect"},
             %MethodCall{receiver: "state", method: "canvas"},
             %MethodCall{receiver: "state . canvas ()", method: "clip_path"}
           ]
  end
end
