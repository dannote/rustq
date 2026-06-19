defmodule RustQ.NativeDescriptorTest do
  use ExUnit.Case, async: true

  test "resolves native refs through Syn indexes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "rustq_native_descriptor_#{System.unique_integer([:positive])}.rs"
      )

    Process.put(:path, path)

    File.write!(path, """
    impl Canvas {
      pub fn draw_rect(&self, rect: impl AsRef<Rect>, paint: &Paint) -> &Self { self }
    }
    """)

    index = RustQ.Syn.Index.from_paths([path])
    ref = RustQ.NativeRef.new("Canvas", "draw_rect")

    assert %RustQ.NativeDescriptor{ref: ^ref, method: method, source_url: nil} =
             RustQ.NativeDescriptor.resolve!(index, ref)

    assert method.name == "draw_rect"

    assert RustQ.Syn.Signature.render(method.signature_ast) ==
             "fn draw_rect(&self, rect: impl AsRef<Rect>, paint: &Paint) -> &Self"
  after
    if path = Process.get(:path), do: File.rm(path)
  end

  test "validates method shape" do
    path =
      Path.join(
        System.tmp_dir!(),
        "rustq_native_descriptor_shape_#{System.unique_integer([:positive])}.rs"
      )

    Process.put(:path, path)

    File.write!(path, """
    impl Canvas {
      pub fn draw_rect(&self, rect: impl AsRef<Rect>, paint: &Paint) -> &Self { self }
    }
    """)

    index = RustQ.Syn.Index.from_paths([path])
    ref = RustQ.NativeRef.new("Canvas", "draw_rect")

    assert %RustQ.NativeDescriptor{} =
             RustQ.NativeDescriptor.resolve!(index, ref,
               args: [:self_ref, {:impl_trait, "AsRef", ["Rect"]}, {:ref, "Paint"}],
               returns: {:ref, "Self"}
             )

    assert_raise RuntimeError, ~r/unexpected native args/, fn ->
      RustQ.NativeDescriptor.resolve!(index, ref, args: [:self_ref, {:path, "Rect"}])
    end
  after
    if path = Process.get(:path), do: File.rm(path)
  end

  test "validates package mismatch" do
    index = %RustQ.Syn.Index{package: %RustQ.Cargo.Package{name: "one"}}
    ref = RustQ.NativeRef.new("Canvas", "draw_rect", package: "two")

    assert_raise ArgumentError, ~r/does not match indexed package/, fn ->
      RustQ.NativeDescriptor.resolve!(index, ref)
    end
  end
end
