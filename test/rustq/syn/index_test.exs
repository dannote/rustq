defmodule RustQ.Syn.IndexTest do
  use ExUnit.Case, async: true

  test "builds package-aware indexes from Cargo metadata" do
    index =
      RustQ.Syn.Index.from_package("rustq_nif", manifest_path: "native/rustq_nif/Cargo.toml")

    assert %RustQ.Cargo.Package{name: "rustq_nif"} = index.package
    assert map_size(index.files) > 0
  end

  test "indexes enums by name" do
    path =
      write_source!("""
      pub enum ClipOp { Intersect, Difference }
      """)

    index = RustQ.Syn.Index.from_paths([path])

    assert [%RustQ.Syn.Enum{name: "ClipOp"}] = RustQ.Syn.Index.enums(index)

    assert {:ok, %RustQ.Syn.Enum{variants: ["Intersect", "Difference"]}} =
             RustQ.Syn.Index.enum(index, "ClipOp")

    assert %RustQ.Syn.Enum{name: "ClipOp"} = RustQ.Syn.Index.enum!(index, "ClipOp")
  end

  test "indexes impl methods by target" do
    path =
      Path.join(
        System.tmp_dir!(),
        "rustq_syn_index_test_#{System.unique_integer([:positive])}.rs"
      )

    Process.put(:path, path)

    File.write!(path, """
    impl Canvas {
      pub fn draw_rect(&self, rect: impl AsRef<Rect>, paint: &Paint) -> &Self { self }
    }

    impl Path {
      pub fn op(&self, other: &Path, op: PathOp) -> Option<Path> { None }
    }
    """)

    index = RustQ.Syn.Index.from_paths([path])

    assert %RustQ.Syn.Method{name: "draw_rect", source_path: ^path, source_line: 2} =
             RustQ.Syn.Index.method!(index, "Canvas", "draw_rect")

    assert {:ok, %RustQ.Syn.Method{name: "op"}} = RustQ.Syn.Index.method(index, "Path", "op")
    assert :error = RustQ.Syn.Index.method(index, "Canvas", "missing")
  after
    if path = Process.get(:path), do: File.rm(path)
  end

  test "type helper predicates match common Rust type shapes" do
    [method] =
      """
      impl Canvas {
        pub fn draw_rect(&self, rect: impl AsRef<Rect>, paint: &Paint) -> &Self { self }
      }
      """
      |> RustQ.Syn.parse!()
      |> RustQ.Syn.methods()

    [self_arg, rect_arg, paint_arg] = method.args

    assert %RustQ.Syn.Type.Ref{} = self_arg.type_ast
    assert RustQ.Syn.Type.impl_trait?(rect_arg.type_ast, "AsRef", ["Rect"])
    assert RustQ.Syn.Type.ref_to?(paint_arg.type_ast, "Paint")
  end

  defp write_source!(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "rustq_syn_index_test_#{System.unique_integer([:positive])}.rs"
      )

    Process.put(:path, path)
    File.write!(path, source)
    path
  end
end
