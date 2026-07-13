defmodule RustQ.PipelineTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [function: 3]

  require A
  require I

  test "binds identifiers, expressions, and splices fields/methods" do
    template = """
    pub struct __rq_Resource {
        __rq_fields: (),
    }

    impl __rq_Resource {
        __rq_methods!();

        pub fn table() -> &'static str {
            __rq_table_name!()
        }
    }
    """

    code =
      template
      |> RustQ.parse!("resource.rs")
      |> RustQ.bind(Resource: :User, table_name: {:literal, "users"})
      |> RustQ.splice(:fields, [
        I.field(:id, :i64, vis: :pub),
        I.field(:name, :String, vis: :pub)
      ])
      |> RustQ.splice(:methods, [
        function :new,
          vis: :pub,
          args: [id: :i64, name: :String],
          returns: :Self do
          A.return(A.struct_expr(:Self, id: A.var(:id), name: A.var(:name)))
        end
      ])
      |> RustQ.render!()

    assert code =~ "pub struct User"
    assert code =~ "pub id: i64"
    assert code =~ "pub name: String"
    assert code =~ "pub fn new(id: i64, name: String) -> Self"
    assert code =~ ~s("users")
  end

  test "does not replace placeholders inside Rust macro token trees" do
    code =
      "fn log() { println!(\"{}\", __rq_value!()); }"
      |> RustQ.render!("macro.rs", bind: [value: {:literal, "hello"}])

    assert code =~ "__rq_value!()"
  end

  test "renders type bindings" do
    code =
      "type MaybeUser = __rq_user!();"
      |> RustQ.render!("types.rs", bind: [user: {:type, {:option, :User}}])

    assert code =~ "type MaybeUser = Option<User>;"
  end

  test "optionally formats generated code with rustfmt" do
    assert RustQ.render!("fn answer()->i32{42}", "answer.rs", rustfmt: true) ==
             "fn answer() -> i32 {\n    42\n}\n"
  end

  test "returns structured rustfmt errors" do
    assert {:error, [%{type: :rustfmt_error, command: "definitely-not-rustfmt", reason: :enoent}]} =
             RustQ.render("fn answer()->i32{42}", "answer.rs", rustfmt: "definitely-not-rustfmt")
  end

  test "prepends preambles after codegen" do
    template = RustQ.parse!("fn answer() -> i32 { 42 }", "answer.rs")

    assert RustQ.render!(template, preamble: "// generated\n\n") ==
             "// generated\n\nfn answer() -> i32 {\n    42\n}\n"

    assert RustQ.render!("fn answer() -> i32 { 42 }", "answer.rs",
             preamble: ["// generated", "\n\n"]
           ) ==
             "// generated\n\nfn answer() -> i32 {\n    42\n}\n"
  end

  test "uses fragment wrappers" do
    code =
      """
      __rq_items!();

      pub fn run() -> i32 {
          __rq_body!();
          __rq_value!()
      }
      """
      |> RustQ.render!("fragments.rs",
        bind: [value: Rust.fragment(:expr, "answer")],
        splice: [
          items: [Rust.fragment(:item, "const answer: i32 = 42;")],
          body: [Rust.fragment(:stmt, "let answer = answer + 1;")]
        ]
      )

    assert code =~ "const answer: i32 = 42;"
    assert code =~ "let answer = answer + 1;"
    assert code =~ "answer\n}"
  end
end
