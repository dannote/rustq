defmodule RustQ.NativeDescriptorTest do
  use ExUnit.Case, async: true

  alias RustQ.Cargo.Package
  alias RustQ.NativeDescriptor
  alias RustQ.NativeRef
  alias RustQ.Syn.Index
  alias RustQ.Syn.Signature

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

    index = Index.from_paths([path])
    ref = NativeRef.new("Canvas", "draw_rect")

    assert %NativeDescriptor{ref: ^ref, method: method, source_url: nil} =
             NativeDescriptor.resolve!(index, ref)

    assert method.name == "draw_rect"

    assert Signature.render(method.signature_ast) ==
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

    index = Index.from_paths([path])
    ref = NativeRef.new("Canvas", "draw_rect")

    assert %NativeDescriptor{} =
             NativeDescriptor.resolve!(index, ref,
               args: [:self_ref, {:impl_trait, "AsRef", ["Rect"]}, {:ref, "Paint"}],
               returns: {:ref, "Self"}
             )

    assert_raise RuntimeError, ~r/unexpected native args/, fn ->
      NativeDescriptor.resolve!(index, ref, args: [:self_ref, {:path, "Rect"}])
    end
  after
    if path = Process.get(:path), do: File.rm(path)
  end

  test "validates package mismatch" do
    index = %Index{package: %Package{name: "one"}}
    ref = NativeRef.new("Canvas", "draw_rect", package: "two")

    assert_raise ArgumentError, ~r/does not match indexed package/, fn ->
      NativeDescriptor.resolve!(index, ref)
    end
  end
end
