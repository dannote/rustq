defmodule RustQ.RustTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust

  test "builds module, const, and type alias items" do
    module =
      :users
      |> Rust.mod()
      |> Rust.pub()
      |> Rust.item(Rust.type_alias(:UserId, :i64, vis: :pub))
      |> Rust.item(Rust.const(:TABLE, {:ref, :str}, Rust.expr(~s("users")), vis: :pub))

    code = RustQ.render!("__splice_items!();", "items.rs", splice: [items: [module]])

    assert code =~ "pub mod users"
    assert code =~ "pub type UserId = i64;"
    assert code =~ ~s|pub const TABLE: &str = "users";|
  end

  test "builds ergonomic generic and lifetime types" do
    assert Rust.type(:Term, lifetime: :a) == "Term<'a>"
    assert Rust.type(:Decoder, lifetime: :_) == "Decoder<'_>"
    assert Rust.path([:std, :sync, :OnceLock]) == "std::sync::OnceLock"
    assert Rust.type(:ResourceArc, [:Document]) == "ResourceArc<Document>"
    assert Rust.ref(:Document, lifetime: :static) == "&'static Document"
    assert Rust.static_slice(:Atom) == "&'static [Atom]"
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
      "__splice_items!();"
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
