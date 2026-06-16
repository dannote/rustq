Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.TypeItemsTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.GeneratedCase, as: Generated

  test "set-theoretic type aliases are available to specs" do
    assert %RustQ.Meta.Type{kind: :enum, rust: "Mode", meta: %{variants: [:src_over, :multiply]}} =
             Generated.__rustq_types__()[{:mode, 0}]

    assert %RustQ.Meta.Type{kind: :struct, rust: "Click", meta: %{fields: click_fields}} =
             Generated.__rustq_types__()[{:click, 0}]

    assert Enum.any?(
             click_fields,
             &match?({:name, %RustQ.Meta.Type{rust: "String"}, :required}, &1)
           )

    assert %RustQ.Meta.Type{kind: :tuple_enum, rust: "Event", meta: %{variants: event_variants}} =
             Generated.__rustq_types__()[{:event, 0}]

    assert {:Click, [%RustQ.Meta.Type{rust: "Click"}]} = List.keyfind(event_variants, :Click, 0)

    assert {:Resize, [%RustQ.Meta.Type{rust: "Resize"}]} =
             List.keyfind(event_variants, :Resize, 0)

    assert %RustQ.Meta.Type{
             kind: :struct,
             rust: "RectOpts<'a>",
             ast: %RustQ.Rust.AST.TypePath{parts: ["RectOpts"], lifetimes: [:a]},
             meta: %{fields: fields}
           } = Generated.__rustq_types__()[{:rect_opts, 0}]

    assert Enum.any?(fields, &match?({:x, %RustQ.Meta.Type{rust: "f32"}, :required}, &1))
    assert Enum.any?(fields, &match?({:fill, %RustQ.Meta.Type{rust: "Term<'a>"}, :optional}, &1))
  end

  test "type aliases generate Rust items and decoders" do
    source = Generated.__rustq_source__()

    assert source =~ "pub enum Mode"
    assert source =~ "SrcOver,"
    assert source =~ "pub fn decode_mode_atom(value: Atom) -> NifResult<Mode>"

    assert source =~ "pub struct Click"
    assert source =~ "pub name: String,"
    assert source =~ "pub struct Resize"
    assert source =~ "pub width: u32,"

    assert source =~ "pub enum Event"
    assert source =~ "Click(Click),"
    assert source =~ "Resize(Resize),"
    assert source =~ "pub fn decode_event<'a>(term: Term<'a>) -> NifResult<Event>"
    assert source =~ ~s|"Elixir.Click" => decode_click(term).map(Event::Click)|

    assert source =~ "pub struct RectOpts"
    assert source =~ "pub x: f32,"
    assert source =~ "pub fill: Option<Term<'a>>,"
    assert source =~ "pub fn decode_rect_opts<'a>(term: Term<'a>) -> NifResult<RectOpts<'a>>"
    assert source =~ "x: term.map_get(atoms::x())?.decode()?"
    assert source =~ "Ok(value) => Some(value.decode()?)"
  end
end
