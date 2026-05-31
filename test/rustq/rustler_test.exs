defmodule RustQ.RustlerTest do
  use ExUnit.Case, async: true

  test "builds Rustler helpers" do
    code =
      "__splice_items!();"
      |> RustQ.render!("native.rs",
        splice: [
          items: [
            RustQ.Rustler.atoms([:ok, :error, {"r#type", "type"}]),
            RustQ.Rustler.nif(:add, args: [a: :i64, b: :i64], returns: :i64, body: "a + b"),
            RustQ.Rustler.init(RustQ.Native)
          ]
        ]
      )

    assert code =~ "rustler::atoms!"
    assert code =~ "#[rustler::nif]"
    assert code =~ "fn add(a: i64, b: i64) -> i64"
    assert code =~ ~s|rustler::init!("Elixir.RustQ.Native");|
  end

  test "builds resource boilerplate" do
    code =
      "__splice_items!();"
      |> RustQ.render!("resource.rs",
        splice: [
          items: RustQ.Rustler.resource(:EncodedImage, fields: [bytes: {:vec, :u8}])
        ]
      )

    assert code =~ "struct EncodedImage"
    assert code =~ "pub bytes: Vec<u8>"
    assert code =~ "#[rustler::resource_impl]"
    assert code =~ "impl rustler::Resource for EncodedImage"
  end

  test "builds option struct decoders" do
    code =
      "__splice_items!();"
      |> RustQ.render!("opts.rs",
        splice: [
          items:
            RustQ.Rustler.opts_decoder(:RectOpts,
              lifetime: :a,
              fields: [
                x: [type: :f32, decode: "opt_f32(opts, atoms::x())?"],
                fill: [type: {:option, "Term<'a>"}, decode: "opt_term(opts, atoms::fill())"]
              ]
            )
        ]
      )

    assert code =~ "pub struct RectOpts<'a>"
    assert code =~ "pub x: f32"
    assert code =~ "pub fill: Option<Term<'a>>"

    assert code =~
             "pub fn decode_rect_opts<'a>(opts: &[(Atom, Term<'a>)]) -> NifResult<RectOpts<'a>>"

    assert code =~ "x: opt_f32(opts, atoms::x())?"
    assert code =~ "fill: opt_term(opts, atoms::fill())"
    assert code =~ "_phantom: std::marker::PhantomData"
  end

  test "builds bare atoms blocks" do
    code =
      RustQ.render!("__splice_items!();", "atoms.rs",
        splice: [items: [RustQ.Rustler.atoms([:ok], module: false)]]
      )

    assert code =~ "rustler::atoms!"
    refute code =~ "mod atoms"
  end
end
