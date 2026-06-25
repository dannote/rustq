defmodule RustQ.Binding.CallableTest do
  use ExUnit.Case, async: true

  alias RustQ.Binding.Callable
  alias RustQ.Cargo.Package
  alias RustQ.Meta.Type
  alias RustQ.Native.Descriptor
  alias RustQ.Native.Ref
  alias RustQ.Syn
  alias RustQ.Syn.Index

  test "normalizes parsed Rust free functions" do
    function =
      """
      pub fn decode(term: Term) -> NifResult<Foo> { todo!() }
      """
      |> parsed_file!()
      |> Syn.functions()
      |> List.first()

    assert %Callable{
             name: "decode",
             kind: :function,
             target: nil,
             args: [%{name: "term", type: %Type{kind: :term, rust: "Term"}}],
             returns: %Type{kind: :nif_result, rust: "NifResult<Foo>"}
           } = Callable.from_syn_function(function)
  end

  test "normalizes parsed nested Rust free functions with module targets" do
    function =
      """
      pub mod color_filters {
        pub fn blend(c: impl Into<Color>, mode: BlendMode) -> Option<ColorFilter> { todo!() }
      }
      """
      |> parsed_file!()
      |> Syn.functions()
      |> List.first()

    assert %Callable{
             name: "blend",
             kind: :function,
             target: "color_filters",
             args: [
               %{name: "c", type: %Type{kind: :impl_trait}},
               %{name: "mode", type: %Type{kind: :type, rust: "BlendMode"}}
             ],
             returns: %Type{kind: :option, rust: "Option<ColorFilter>"}
           } = Callable.from_syn_function(function)
  end

  test "normalizes parsed Rust impl methods with receiver and return metadata" do
    method =
      """
      impl Canvas {
        pub fn draw_rect(&self, rect: Rect) -> &Self { self }
      }
      """
      |> parsed_file!()
      |> Syn.methods()
      |> List.first()

    assert %Callable{
             name: "draw_rect",
             kind: :method,
             target: "Canvas",
             args: [
               %{name: "self", type: %Type{kind: :ref, rust: "&Self"}},
               %{name: "rect", type: %Type{kind: :type, rust: "Rect"}}
             ],
             returns: %Type{kind: :ref, rust: "&Self"}
           } = Callable.from_syn_method(method, target: "Canvas")
  end

  test "normalizes option and result return types" do
    callables =
      """
      pub fn maybe_path() -> Option<Path> { todo!() }
      pub fn fallible_image() -> Result<Image, Error> { todo!() }
      """
      |> parsed_file!()
      |> Syn.functions()
      |> Enum.map(&Callable.from_syn_function/1)

    assert %Callable{returns: %Type{kind: :option, rust: "Option<Path>"}} =
             Enum.find(callables, &(&1.name == "maybe_path"))

    assert %Callable{returns: %Type{kind: :result, rust: "Result<Image, Error>"}} =
             Enum.find(callables, &(&1.name == "fallible_image"))
  end

  test "normalizes resolved native descriptors" do
    path =
      tmp_rust!("native_descriptor_callable", """
      impl Canvas {
        pub fn clear(&mut self, color: Color) -> &mut Self { self }
      }
      """)

    index = %Index{Index.from_paths([path]) | package: %Package{name: "skia-safe"}}
    ref = Ref.new("Canvas", "clear", package: "skia-safe")
    descriptor = Descriptor.resolve!(index, ref)

    assert %Callable{
             name: "clear",
             kind: :method,
             target: "Canvas",
             native_ref: ^ref,
             args: [
               %{name: "self", type: %Type{kind: :mut_ref, rust: "&mut Self"}},
               %{name: "color", type: %Type{kind: :type, rust: "Color"}}
             ],
             returns: %Type{kind: :mut_ref, rust: "&mut Self"}
           } = Callable.from_native_descriptor(descriptor)
  after
    cleanup_tmp_rust()
  end

  defp parsed_file!(source) do
    path = tmp_rust!("callable", source)
    Syn.parse_file!(path)
  end

  defp tmp_rust!(name, source) do
    path = Path.join(System.tmp_dir!(), "rustq_#{name}_#{System.unique_integer([:positive])}.rs")
    Process.put({__MODULE__, :tmp_paths}, [path | Process.get({__MODULE__, :tmp_paths}, [])])
    File.write!(path, source)
    path
  end

  defp cleanup_tmp_rust do
    {__MODULE__, :tmp_paths}
    |> Process.get([])
    |> Enum.each(&File.rm/1)

    Process.delete({__MODULE__, :tmp_paths})
  end
end
