defmodule RustQ.PipelineTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "binds identifiers, expressions, and splices fields/methods" do
    template = """
    pub struct __Resource {
        __splice_fields: (),
    }

    impl __Resource {
        __splice_methods!();

        pub fn table() -> &'static str {
            __expr_table_name!()
        }
    }
    """

    code =
      template
      |> RustQ.parse!("resource.rs")
      |> RustQ.bind(Resource: :User, table_name: {:literal, "users"})
      |> RustQ.splice(:fields, [
        Rust.field(:id, :i64, vis: :pub),
        Rust.field(:name, :String, vis: :pub)
      ])
      |> RustQ.splice(:methods, [
        Rust.fn(:new,
          vis: :pub,
          args: [id: :i64, name: :String],
          returns: :Self,
          body: "Self { id, name }"
        )
      ])
      |> RustQ.codegen!()

    assert code =~ "pub struct User"
    assert code =~ "pub id: i64"
    assert code =~ "pub name: String"
    assert code =~ "pub fn new(id: i64, name: String) -> Self"
    assert code =~ ~s("users")
  end

  test "renders type bindings" do
    code =
      "type MaybeUser = __type_user!();"
      |> RustQ.render!("types.rs", bind: [user: {:type, {:option, :User}}])

    assert code =~ "type MaybeUser = Option<User>;"
  end

  test "prepends preambles after codegen" do
    template = RustQ.parse!("fn answer() -> i32 { 42 }", "answer.rs")

    assert RustQ.codegen!(template, preamble: "// generated\n\n") ==
             "// generated\n\nfn answer() -> i32 {\n    42\n}\n"

    assert RustQ.render!("fn answer() -> i32 { 42 }", "answer.rs",
             preamble: ["// generated", "\n\n"]
           ) ==
             "// generated\n\nfn answer() -> i32 {\n    42\n}\n"
  end

  test "uses fragment wrappers" do
    code =
      """
      __splice_items!();

      pub fn run() -> i32 {
          __splice_body!();
          __expr_value!()
      }
      """
      |> RustQ.render!("fragments.rs",
        bind: [value: Rust.expr("answer")],
        splice: [
          items: [Rust.item("const answer: i32 = 42;")],
          body: [Rust.stmt("let answer = answer + 1;")]
        ]
      )

    assert code =~ "const answer: i32 = 42;"
    assert code =~ "let answer = answer + 1;"
    assert code =~ "answer\n}"
  end
end
