defmodule RustQ.RustlerTest do
  use ExUnit.Case, async: true

  test "builds Rustler helpers" do
    code =
      "__rq_items!();"
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

  test "builds cached atom functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("cached_atoms.rs",
        splice: [items: RustQ.Rustler.cached_atoms([:ok, {:node_changes, "nodeChanges"}])]
      )

    assert code =~ "fn cached_atom(env: Env, cell: &'static OnceLock<Atom>, name: &str) -> Atom"
    assert code =~ "static OK_ATOM: OnceLock<Atom> = OnceLock::new();"
    assert code =~ "fn ok_atom(env: Env) -> Atom"
    assert code =~ ~S/cached_atom(env, &NODE_CHANGES_ATOM, "nodeChanges")/
  end

  test "builds term builder helpers" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_builders.rs", splice: [items: RustQ.Rustler.term_builders()])

    assert code =~ "fn make_map_from_terms<'a>"
    assert code =~ "fn make_struct_from_terms<'a>"
    assert code =~ "Term::map_from_term_arrays"
  end

  test "builds raw NIF_TERM builder helpers" do
    code =
      "__rq_items!();"
      |> RustQ.render!("nif_term_builders.rs", splice: [items: RustQ.Rustler.nif_term_builders()])

    assert code =~ "fn make_map_from_nif_terms<'a>"
    assert code =~ "fn make_struct_from_nif_terms<'a>"
    assert code =~ "rustler::wrapper::map::map_put"
  end

  test "builds NifStruct declarations" do
    code =
      "__rq_items!();"
      |> RustQ.render!("nif_struct.rs",
        splice: [
          items: [
            RustQ.Rustler.nif_struct(:ExText, "Folio.Content.Text",
              fields: [
                text: :String,
                size: {:option, :String}
              ]
            )
          ]
        ]
      )

    assert code =~ "#[derive(Clone, Debug, NifStruct)]"
    assert code =~ ~S/#[module = "Folio.Content.Text"]/
    assert code =~ "pub struct ExText"
    assert code =~ "pub text: String"
    assert code =~ "pub size: Option<String>"
  end

  test "builds tagged enum decoder and encoder declarations" do
    code =
      "__rq_items!();"
      |> RustQ.render!("tagged_enum.rs",
        splice: [
          items:
            RustQ.Rustler.tagged_enum(:ExContent,
              tag: "atom_struct()",
              attrs: ["allow(dead_code)"],
              variants: [
                Text: [type: :ExText, module: "Elixir.Folio.Content.Text"],
                Space: [type: :ExSpace, module: "Elixir.Folio.Content.Space"]
              ]
            )
        ]
      )

    assert code =~ "#[allow(dead_code)]"
    assert code =~ "pub enum ExContent"
    assert code =~ "Text(ExText)"
    assert code =~ "impl<'a> rustler::Decoder<'a> for ExContent"
    assert code =~ ~S/"Elixir.Folio.Content.Text" => Ok(ExContent::Text(Decoder::decode(term)?))/
    assert code =~ "impl rustler::Encoder for ExContent"
    assert code =~ "ExContent::Text(value) => value.encode(env)"
  end

  test "builds term helper functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_helpers.rs",
        splice: [items: RustQ.Rustler.term_helpers(type_key: "a::r#type()")]
      )

    assert code =~ "fn get<'a>(term: Term<'a>, key: rustler::Atom) -> Option<Term<'a>>"
    assert code =~ "fn opt<'a>(term: Term<'a>, key: rustler::Atom) -> Option<Term<'a>>"
    assert code =~ "fn str_val<'a>(term: Term<'a>, key: rustler::Atom) -> String"
    assert code =~ "get(term, a::r#type())"
  end

  test "builds term decoders" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_decoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_decoder(:User,
              fields: [
                id: [type: :i64, key: "a::id()", required: true],
                name: [type: :String, key: "a::name()", required: true],
                active: [type: :bool, key: "a::active()", default: "false"],
                email: [type: {:option, :String}, key: "a::email()"],
                body: [type: {:vec, "Term<'a>"}, decode: "list_val(term, a::body())"]
              ]
            )
        ]
      )

    assert code =~ "struct User<'a>"
    assert code =~ "fn decode_user<'a>(term: Term<'a>) -> NifResult<User<'a>>"
    assert code =~ "id: term.map_get(a::id())?.decode::<i64>()?"
    assert code =~ "name: term.map_get(a::name())?.decode::<String>()?"
    assert code =~ "unwrap_or(false)"
    assert code =~ "email: term.map_get(a::email()).ok()"
    assert code =~ "body: list_val(term, a::body())"
  end

  test "builds term decoders with custom result aliases" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_decoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_decoder(:IfStatementInput,
              result: "R",
              fields: [
                test: [type: "Term<'a>", key: "a::test()", required: true],
                alternate: [type: {:option, "Term<'a>"}, key: "a::alternate()"]
              ]
            )
        ]
      )

    assert code =~ "fn decode_if_statement_input<'a>(term: Term<'a>) -> R<IfStatementInput<'a>>"
    assert code =~ ~S/map_err(|_| "Missing :test".to_string())?/
    assert code =~ ~S/map_err(|_| "Invalid :test".to_string())?/
    assert code =~ "alternate: term"
    assert code =~ ".map_get(a::alternate())"
  end

  test "builds term decoders with custom required error messages" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_decoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_decoder(:IfStatementInput,
              result: "R",
              fields: [
                test: [
                  type: "Term<'a>",
                  key: "a::test()",
                  required: true,
                  missing: "Missing condition",
                  invalid: "Invalid condition"
                ]
              ]
            )
        ]
      )

    assert code =~ ~S/map_err(|_| "Missing condition".to_string())?/
    assert code =~ ~S/map_err(|_| "Invalid condition".to_string())?/
  end

  test "selects term helper functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_helpers.rs",
        splice: [items: RustQ.Rustler.term_helpers(include: [:get, :str_val])]
      )

    assert code =~ "fn get<'a>"
    assert code =~ "fn str_val<'a>"
    refute code =~ "fn bool_val"
    refute code =~ "fn type_atom"
  end

  test "supports explicit all term helper selection" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_helpers.rs",
        splice: [items: RustQ.Rustler.term_helpers(include: :all)]
      )

    assert code =~ "fn get<'a>"
    assert code =~ "fn type_str"
  end

  test "excludes term helper functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_helpers.rs",
        splice: [items: RustQ.Rustler.term_helpers(exclude: [:f64_val, :type_str])]
      )

    assert code =~ "fn get<'a>"
    refute code =~ "fn f64_val"
    refute code =~ "fn type_str"
  end

  test "builds resource helper boilerplate" do
    code =
      "__rq_items!();"
      |> RustQ.render!("resource.rs",
        splice: [
          items: [
            RustQ.Rustler.resource_type(:Document),
            RustQ.Rustler.resource_decoder(:Document),
            RustQ.Rustler.resource_init(:Document)
          ]
        ]
      )

    assert RustQ.Rustler.resource_arc(:Document) == "ResourceArc<Document>"
    assert code =~ "type DocumentResource = ResourceArc<Document>;"

    assert code =~
             "fn decode_document_resource<'a>(term: Term<'a>) -> NifResult<ResourceArc<Document>>"

    assert code =~ "rustler::resource!(Document, env);"
  end

  test "builds resource boilerplate" do
    code =
      "__rq_items!();"
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
      "__rq_items!();"
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
      RustQ.render!("__rq_items!();", "atoms.rs",
        splice: [items: [RustQ.Rustler.atoms([:ok], module: false)]]
      )

    assert code =~ "rustler::atoms!"
    refute code =~ "mod atoms"
  end
end
