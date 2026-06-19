defmodule RustQ.RustTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.TypeBuilder, as: T

  test "builds module, const, and type alias items" do
    module =
      :users
      |> Rust.mod()
      |> Rust.pub()
      |> Rust.item(Rust.type_alias(:UserId, :i64, vis: :pub))
      |> Rust.item(Rust.const(:TABLE, {:ref, :str}, Rust.expr(~s("users")), vis: :pub))

    code = RustQ.render!("__rq_items!();", "items.rs", splice: [items: [module]])

    assert code =~ "pub mod users"
    assert code =~ "pub type UserId = i64;"
    assert code =~ ~s|pub const TABLE: &str = "users";|
  end

  test "converts Rust AST items to fragments" do
    item = A.const(:ANSWER, :i32, A.lit(42))

    assert Rust.ast_item(item) |> Rust.to_fragment() == "const ANSWER: i32 = 42;"
  end

  test "builds ergonomic generic and lifetime types" do
    assert Rust.type(:Term, lifetime: :a) == "Term<'a>"
    assert Rust.type(:Decoder, lifetime: :_) == "Decoder<'_>"
    assert Rust.path([:std, :sync, :OnceLock]) == "std::sync::OnceLock"
    assert Rust.type(:ResourceArc, [:Document]) == "ResourceArc<Document>"
    assert Rust.ref(:Document, lifetime: :static) == "&'static Document"
    assert Rust.static_slice(:Atom) == "&'static [Atom]"
    assert Rust.type(T.ref(T.slice(T.ref(:str)))) == "&[&str]"
  end

  test "builds functions with generics and where clauses" do
    code =
      Rust.fn(:read_repeated,
        lifetime: :a,
        generics: [:T, :F],
        args: [decoder: {:ref, :Decoder}],
        returns: {:raw, "NifResult<T>"},
        where: ["F: FnMut(&mut Self) -> NifResult<T>"],
        body: "todo!()"
      )
      |> Rust.to_fragment()

    assert code =~ "fn read_repeated<'a, T, F>"
    assert code =~ "where\n    F: FnMut(&mut Self) -> NifResult<T>"
  end

  test "builds generic expression fragments" do
    assert Rust.call_expr("paint", :color, []) |> Rust.to_fragment() == "paint.color()"
    assert Rust.some("value") |> Rust.to_fragment() == "Some(value)"
    assert Rust.none() |> Rust.to_fragment() == "None"
    assert Rust.tuple(["x", "y"]) |> Rust.to_fragment() == "(x, y)"
    assert Rust.cast("alpha", "u8") |> Rust.to_fragment() == "alpha as u8"
    assert Rust.question("decode(term)") |> Rust.to_fragment() == "decode(term)?"
    assert Rust.ref_expr("paint", mut: true) |> Rust.to_fragment() == "&mut paint"
  end

  test "builds generic statement and control-flow fragments" do
    body =
      Rust.block([
        Rust.let_mut("paint", "Paint::default()"),
        Rust.call_stmt("paint", :set_anti_alias, ["true"]),
        Rust.if_let("Some(alpha)", "opts.alpha", [
          Rust.call_stmt("paint", :set_alpha, ["alpha"])
        ]),
        Rust.if_(
          "radius > 0.0",
          [
            Rust.call_stmt("canvas", :draw_rrect, ["rrect", "&paint"])
          ],
          else: [Rust.call_stmt("canvas", :draw_rect, ["rect", "&paint"])]
        ),
        Rust.match_("mode", [
          {"Mode::A", [Rust.call_stmt("canvas", :save, [])]},
          {"_", [Rust.return_if("failed")]}
        ])
      ])
      |> Rust.to_fragment()

    assert body =~ "let mut paint = Paint::default();"
    assert body =~ "paint.set_anti_alias(true);"
    assert body =~ "if let Some(alpha) = opts.alpha"
    assert body =~ "} else {"
    assert body =~ "match mode"
    assert body =~ "_ => {"
    assert body =~ "if failed { return Ok(()); }"
  end

  test "builds top-level Rust items" do
    user =
      :User
      |> Rust.struct()
      |> Rust.pub()
      |> Rust.derive([:Debug, :Clone])
      |> Rust.field(:id, :i64, vis: :pub)
      |> Rust.field(:name, :String, vis: :pub)

    event =
      :Event
      |> Rust.enum()
      |> Rust.pub()
      |> Rust.variant(:Started)
      |> Rust.variant({:Stopped, fields: [reason: :String]})
      |> Rust.variant({:Data, tuple: [:String, :u64]})

    new_fn =
      :new
      |> Rust.fn()
      |> Rust.pub()
      |> Rust.args(id: :i64, name: :String)
      |> Rust.returns(:Self)
      |> Rust.body("Self { id, name }")

    impl =
      :User
      |> Rust.impl()
      |> Rust.item(new_fn)

    code =
      "__rq_items!();"
      |> RustQ.render!("items.rs",
        splice: [items: [Rust.use([:std, :collections, :HashMap]), user, event, impl]]
      )

    assert code =~ "use std::collections::HashMap;"
    assert code =~ "#[derive(Debug, Clone)]"
    assert code =~ "pub struct User"
    assert code =~ "pub enum Event"
    assert code =~ "Stopped { reason: String }"
    assert code =~ "Data(String, u64)"
    assert code =~ "impl User"
  end
end
