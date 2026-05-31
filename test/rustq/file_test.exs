defmodule RustQ.FileTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "loads and renders template files" do
    path = tmp_template_path()
    File.write!(path, "pub struct __Name { __splice_fields: (), }")

    code =
      path
      |> RustQ.from_file!()
      |> RustQ.bind(Name: :User)
      |> RustQ.splice(:fields, Rust.field(:id, :i64, vis: :pub))
      |> RustQ.codegen!()

    assert code =~ "pub struct User"
    assert code =~ "pub id: i64"

    assert {:ok, rendered} =
             RustQ.render_file(path, bind: [Name: :Post], splice: [fields: Rust.field(:id, :i64)])

    assert rendered =~ "struct Post"
  after
    if path = Process.get(:rustq_template_path), do: File.rm(path)
  end

  defp tmp_template_path do
    path =
      Path.join(System.tmp_dir!(), "rustq-template-") <>
        Integer.to_string(System.unique_integer([:positive])) <> ".rs"

    Process.put(:rustq_template_path, path)
    path
  end
end
