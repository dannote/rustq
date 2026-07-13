defmodule RustQ.RustTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I
  alias RustQ.Rust.AST.TypeBuilder, as: T
  alias RustQ.Rust.Identifier

  test "renders structural Rust items" do
    module =
      A.module(
        :users,
        [
          A.type_alias(:UserId, :i64, vis: :pub),
          A.const(:TABLE, T.ref(:str), A.lit("users"), vis: :pub)
        ],
        vis: :pub
      )

    code = RustQ.render!("__rq_items!();", "items.rs", splice: [items: [module]])

    assert code =~ "pub mod users"
    assert code =~ "pub type UserId = i64;"
    assert code =~ ~s|pub const TABLE: &str = "users";|
  end

  test "renders one AST item explicitly" do
    item = A.const("ANSWER", :i32, A.lit(42))
    assert Rust.render(item) == "const ANSWER: i32 = 42;\n"
  end

  test "converts bounded Rust identifiers safely" do
    assert Identifier.atom!("generated_name") == :generated_name
    refute Identifier.valid?("not::an::identifier")
    assert_raise ArgumentError, fn -> Identifier.atom!("not::an::identifier") end
  end

  test "renders structural Rust types" do
    assert Rust.render_type(T.path(:Term, lifetimes: [:a])) == "Term<'a>"
    assert Rust.render_type(T.ref(:Document, lifetime: :static)) == "&'static Document"
    assert Rust.render_type(T.ref(T.slice(T.ref(:str)))) == "&[&str]"

    assert Rust.render_type(T.path(:ResourceArc, generics: [T.path(:Document)])) ==
             "ResourceArc<Document>"
  end

  test "keeps unsupported syntax explicit at fragment boundaries" do
    fragment = Rust.fragment(:item, "unsafe extern \"C\" { fn raw(); }")
    assert Rust.render(fragment) == "unsafe extern \"C\" { fn raw(); }"
  end

  test "renders structural fields for template splices" do
    field = I.field(:id, :i64, vis: :pub)
    assert Rust.render(field) == "pub id: i64,"
  end

  test "renders expression AST at explicit boundaries" do
    assert Rust.render(A.var(:value)) == "value"
  end
end
