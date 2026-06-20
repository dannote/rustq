defmodule RustQ.Native.EnumDescriptorTest do
  use ExUnit.Case, async: true

  alias RustQ.Native.EnumDescriptor
  alias RustQ.Syn.Enum, as: SynEnum
  alias RustQ.Syn.Index

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

    index = Index.from_paths([path])

    assert %EnumDescriptor{
             name: "ClipOp",
             package: nil,
             enum: %SynEnum{variants: ["Intersect", "Difference"]},
             source_url: nil
           } = EnumDescriptor.resolve!(index, "ClipOp")
  after
    if path = Process.get(:path), do: File.rm(path)
  end

  test "validates package mismatch" do
    index = %RustQ.Syn.Index{package: %RustQ.Cargo.Package{name: "one"}}

    assert_raise ArgumentError, ~r/does not match indexed package/, fn ->
      EnumDescriptor.resolve!(index, "ClipOp", package: "two")
    end
  end
end
