defmodule RustQ.NativeEnumDescriptorTest do
  use ExUnit.Case, async: true

  test "resolves native enums through Syn indexes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "rustq_native_enum_descriptor_#{System.unique_integer([:positive])}.rs"
      )

    Process.put(:path, path)

    File.write!(path, """
    pub enum ClipOp { Intersect, Difference }
    """)

    index = RustQ.Syn.Index.from_paths([path])

    assert %RustQ.NativeEnumDescriptor{
             name: "ClipOp",
             package: nil,
             enum: %RustQ.Syn.Enum{variants: ["Intersect", "Difference"]},
             source_url: nil
           } = RustQ.NativeEnumDescriptor.resolve!(index, "ClipOp")
  after
    if path = Process.get(:path), do: File.rm(path)
  end

  test "validates package mismatch" do
    index = %RustQ.Syn.Index{package: %RustQ.Cargo.Package{name: "one"}}

    assert_raise ArgumentError, ~r/does not match indexed package/, fn ->
      RustQ.NativeEnumDescriptor.resolve!(index, "ClipOp", package: "two")
    end
  end
end
