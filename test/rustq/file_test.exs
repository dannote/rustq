defmodule RustQ.FileTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "loads and renders template files" do
    path = tmp_template_path()
    File.write!(path, "pub struct __rq_Name { __rq_fields: (), }")

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

  test "expands relative template includes before parsing and rendering" do
    dir = tmp_template_dir()
    template = Path.join(dir, "main.rs")
    partial = Path.join(dir, "partials/fields.rs")
    nested = Path.join(dir, "partials/methods.rs")

    File.mkdir_p!(Path.dirname(partial))
    File.write!(partial, "pub id: i64,")
    File.write!(nested, "pub fn id(&self) -> i64 { self.id }")

    File.write!(template, """
    pub struct User {
        __rq_include!("partials/fields.rs");
    }

    impl User {
        __rq_include!("partials/methods.rs");
    }
    """)

    code = RustQ.render_file!(template)

    assert code =~ "pub struct User"
    assert code =~ "pub id: i64"
    assert code =~ "pub fn id(&self) -> i64"
  after
    if dir = Process.get(:rustq_template_dir), do: File.rm_rf(dir)
  end

  test "reports include cycles" do
    dir = tmp_template_dir()
    a = Path.join(dir, "a.rs")
    b = Path.join(dir, "b.rs")

    File.mkdir_p!(dir)
    File.write!(a, ~s[__rq_include!("b.rs");])
    File.write!(b, ~s[__rq_include!("a.rs");])

    assert {:error, [%{type: :include_error, message: message, include_stack: include_stack}]} =
             RustQ.render_file(a)

    assert message =~ "cyclic RustQ include"
    assert include_stack == [Path.expand(a), Path.expand(b), Path.expand(a)]
  after
    if dir = Process.get(:rustq_template_dir), do: File.rm_rf(dir)
  end

  defp tmp_template_path do
    path =
      Path.join(System.tmp_dir!(), "rustq-template-") <>
        Integer.to_string(System.unique_integer([:positive])) <> ".rs"

    Process.put(:rustq_template_path, path)
    path
  end

  defp tmp_template_dir do
    path =
      Path.join(System.tmp_dir!(), "rustq-template-dir-") <>
        Integer.to_string(System.unique_integer([:positive]))

    Process.put(:rustq_template_dir, path)
    path
  end
end
