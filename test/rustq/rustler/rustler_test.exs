defmodule RustQ.RustlerTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST.Builder, as: A

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
    assert code =~ ~s|rustler::init! {|
    assert code =~ ~s|"Elixir.RustQ.Native"|
  end

  test "derives NIF export signatures from implementation source" do
    code =
      "__rq_items!();"
      |> RustQ.render!("nif_exports.rs",
        splice: [
          items:
            RustQ.Rustler.nif_exports_from_source(
              "test/fixtures/nif_impls.rs",
              [parse_nif: [], compile_nif: [attrs: [A.allow_attr(:too_many_arguments)]]],
              lifetime: :a,
              schedule: :dirty_cpu
            )
        ]
      )

    assert code =~ ~s|#[rustler::nif(schedule = "DirtyCpu")]|
    assert code =~ "fn parse_nif<'a>(env: Env<'a>, source: &str) -> NifResult<Term<'a>>"
    assert code =~ "parse_nif_impl(env, source)"
    assert code =~ "#[allow(too_many_arguments)]"
    assert code =~ "compile_nif_impl(env, source, minify)"
  end

  test "builds NIF export functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("nif_exports.rs",
        splice: [
          items:
            RustQ.Rustler.nif_exports(
              render_png: [
                args: [env: "Env<'a>", batch: "Term<'a>"],
                returns: "NifResult<Term<'a>>",
                lifetime: :a,
                schedule: :dirty_cpu
              ],
              register_file: [
                args: [path: :String, data: "rustler::Binary<'a>"],
                returns: "rustler::Atom",
                lifetime: :a,
                impl: "files::register"
              ]
            )
        ]
      )

    assert code =~ ~s|#[rustler::nif(schedule = "DirtyCpu")]|
    assert code =~ "fn render_png<'a>(env: Env<'a>, batch: Term<'a>) -> NifResult<Term<'a>>"
    assert code =~ "render_png_impl(env, batch)"
    assert code =~ "#[rustler::nif]"

    assert code =~
             "fn register_file<'a>(path: String, data: rustler::Binary<'a>) -> rustler::Atom"

    assert code =~ "files::register(path, data)"
  end

  test "builds atom decoders" do
    code =
      "__rq_items!();"
      |> RustQ.render!("atom_decoder.rs",
        splice: [
          items: [
            RustQ.Rustler.atom_decoder(:decode_blend_mode,
              returns: :BlendMode,
              cases: [src_over: "BlendMode::SrcOver", multiply: "BlendMode::Multiply"]
            )
          ]
        ]
      )

    assert code =~ "pub fn decode_blend_mode(value: Atom) -> NifResult<BlendMode>"
    assert code =~ "value if value == atoms::src_over() => Ok(BlendMode::SrcOver)"
    assert code =~ "_ => Err(rustler::Error::BadArg)"
  end

  test "builds atom decoders from native enum descriptors" do
    descriptor = %RustQ.Native.EnumDescriptor{
      name: "SkClipOp",
      enum: %RustQ.Syn.Enum{name: "SkClipOp", variants: ["Difference", "Intersect"]}
    }

    code =
      "__rq_items!();"
      |> RustQ.render!("atom_decoder_descriptor.rs",
        splice: [
          items: [
            RustQ.Rustler.atom_decoder(:decode_clip_op,
              returns: :ClipOp,
              descriptor: descriptor
            )
          ]
        ]
      )

    assert code =~ "pub fn decode_clip_op(value: Atom) -> NifResult<ClipOp>"
    assert code =~ "value if value == atoms::difference() => Ok(ClipOp::Difference)"
    assert code =~ "value if value == atoms::intersect() => Ok(ClipOp::Intersect)"
  end

  test "builds atom decoders with string function and case names" do
    code =
      "__rq_items!();"
      |> RustQ.render!("atom_decoder_strings.rs",
        splice: [
          items: [
            RustQ.Rustler.atom_decoder("decode_fill_rule",
              returns: :FillRule,
              cases: [{"even_odd", "FillRule::EvenOdd"}]
            )
          ]
        ]
      )

    assert code =~ "pub fn decode_fill_rule(value: Atom) -> NifResult<FillRule>"
    assert code =~ "value if value == atoms::even_odd() => Ok(FillRule::EvenOdd)"
  end

  test "builds atom dispatch functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("atom_dispatch.rs",
        splice: [
          items: [
            RustQ.Rustler.atom_dispatch(:draw_command,
              lifetime: :a,
              args: [surface: "&mut Surface", command: "Term<'a>"],
              on: "command.map_get(atoms::op())?.decode::<Atom>()?",
              cases: [
                rect: "draw_rect(surface, command)",
                circle: "draw_circle(surface, command)"
              ]
            )
          ]
        ]
      )

    assert code =~
             "fn draw_command<'a>(surface: &mut Surface, command: Term<'a>) -> NifResult<()>"

    assert code =~ "let value = command.map_get(atoms::op())?.decode::<Atom>()?;"
    assert code =~ "value if value == atoms::rect() => draw_rect(surface, command)"
    assert code =~ "_ => Ok(())"
  end

  test "builds atom dispatch functions from AST expressions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("atom_dispatch_ast.rs",
        splice: [
          items: [
            RustQ.Rustler.atom_dispatch(:draw_command,
              on: A.atom(:op),
              cases: [rect: A.call(:draw_rect)],
              unknown: A.err(A.badarg())
            )
          ]
        ]
      )

    assert code =~ "let value = atoms::op();"
    assert code =~ "value if value == atoms::rect() => draw_rect()"
    assert code =~ "_ => Err(rustler::Error::BadArg)"
  end

  test "builds map helper functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("opts_helpers.rs", splice: [items: RustQ.Rustler.opts_helpers()])

    assert code =~ "fn decode_opts<'a>(term: Term<'a>) -> NifResult<Vec<(Atom, Term<'a>)>>"
    assert code =~ "term.map_get(atoms::opts())?"
    assert code =~ "fn decode_args<'a>(term: Term<'a>) -> NifResult<Vec<Term<'a>>>"
    assert code =~ "term.map_get(atoms::args())?"
    assert code =~ "fn opt_term<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> Option<Term<'a>>"
    assert code =~ "fn opt_f32<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> NifResult<f32>"
    assert code =~ "fn opt_atom_option<'a>"
    assert code =~ "Ok(Some(term.decode::<f64>()? as f32))"
    assert code =~ "Ok(Some(term.decode::<bool>()?))"
    assert code =~ "Ok(Some(term.decode::<Atom>()?))"
  end

  test "builds cached atom functions" do
    code =
      "__rq_items!();"
      |> RustQ.render!("cached_atoms.rs",
        splice: [items: RustQ.Rustler.cached_atoms([:ok, {:node_changes, "nodeChanges"}])]
      )

    assert code =~ "fn cached_atom(env: Env, cell: &OnceLock<Atom>, name: &str) -> Atom"
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

  test "builds fixed struct term helpers" do
    code =
      "__rq_items!();"
      |> RustQ.render!("fixed_struct_helpers.rs",
        splice: [
          items:
            RustQ.Rustler.term_helpers(
              include: [
                :cached_struct_keys,
                :default_struct_values,
                :make_struct_from_nif_term_arrays
              ]
            )
        ]
      )

    assert code =~ "fn cached_struct_keys"
    assert code =~ "OnceLock<Vec<rustler::wrapper::NIF_TERM>>"
    assert code =~ "fn default_struct_values"
    assert code =~ ~s|Atom::from_str(env, "nil").unwrap().as_c_arg()|
    assert code =~ "fn make_struct_from_nif_term_arrays<'a>"
    assert code =~ "rustler::wrapper::map::make_map_from_arrays"
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
              tag: A.call(:atom_struct),
              attrs: [A.allow_attr(:dead_code)],
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
    assert code =~ ~S/"Elixir.Folio.Content.Text"/
    assert code =~ "Ok(ExContent::Text(rustler::Decoder::decode(term)?))"
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
    assert code =~ "get(term, atoms::r#type())"
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

  test "builds atom-keyed term encoder implementations" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_encoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_encoder(:EncodedLoc,
              fields: [:start, {:end_, :end}],
              target_lifetimes: [:_]
            )
        ]
      )

    assert code =~ "impl rustler::Encoder for EncodedLoc<'_>"
    assert code =~ "fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a>"
    assert code =~ "atoms::start().encode(env)"
    assert code =~ "atoms::end_().encode(env)"
    assert code =~ "self.end.encode(env)"
    assert code =~ "Term::map_from_arrays"
  end

  test "builds term encoders with nested and transformed fields" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_encoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_encoder(:EncodedBlock,
              fields: [
                content: [field: [0, :content], via: :as_ref],
                lang: [field: [0, :lang], via: :as_deref],
                loc: [field: [0, :loc], with: :loc_to_term],
                exports: [
                  field: [0, :exports],
                  via: :as_ref,
                  with: :encode_exports,
                  borrow: false
                ],
                code: [field: :code_override, fallback: [field: [:result, :code], via: :as_str]]
              ],
              target_lifetimes: [:_]
            )
        ]
      )

    assert code =~ "self.0.content.as_ref().encode(env)"
    assert code =~ "self.0.lang.as_deref().encode(env)"
    assert code =~ "loc_to_term(env, &self.0.loc)"
    assert code =~ "encode_exports(env, self.0.exports.as_ref())"
    assert code =~ "self.code_override.unwrap_or(self.result.code.as_str()).encode(env)"
  end

  test "builds mapped and optional adapter fields" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_encoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_encoder(:EncodedResult,
              fields: [
                template: [field: [:descriptor, :template], optional: [wrap: :EncodedTemplate]],
                styles: [field: [:descriptor, :styles], map: [wrap: :EncodedStyle]],
                errors: [field: [:result, :errors], map: [convert: :EncodedError]],
                warnings: [field: [:result, :warnings], map: [via: :as_str]],
                ast: [field: [:result, :ast], optional: [with: :encode_json_value]]
              ],
              target_lifetimes: [:_]
            )
        ]
      )

    assert code =~ ".template"
    assert code =~ ".map(|value| EncodedTemplate(value).encode(env))"
    assert code =~ ".unwrap_or_else(|| nil_term(env))"
    assert code =~ ".styles"
    assert code =~ ".map(|value| EncodedStyle(value).encode(env))"
    assert code =~ "collect::<Vec<Term<'a>>>()"
    assert code =~ ".encode(env)"
    assert code =~ "EncodedError::from(value).encode(env)"
    assert code =~ "value.as_str().encode(env)"
    assert code =~ "encode_json_value(env, value)"
  end

  test "builds term encoders with conditional option fields" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_encoder.rs",
        splice: [
          items:
            RustQ.Rustler.term_encoder(:EncodedError,
              fields: [:message, code: [field: [0, :module_code], when_some: true, via: :as_str]],
              target_lifetimes: [:_]
            )
        ]
      )

    assert code =~ "let mut keys = vec![atoms::message().encode(env)]"
    assert code =~ "if let Some(value) = self.0.module_code.as_ref()"
    assert code =~ "keys.push(atoms::code().encode(env))"
    assert code =~ "values.push(value.as_str().encode(env))"
    assert code =~ "Term::map_from_arrays(env, &keys, &values)"
  end

  test "builds forgiving optional map decoders" do
    code =
      "__rq_items!();"
      |> RustQ.render!("term_helpers.rs",
        splice: [
          items:
            RustQ.Rustler.term_helpers(
              include: [
                :get,
                :get_bool,
                :get_i64,
                :get_string,
                :get_string_list,
                :get_term_list,
                :get_map
              ]
            )
        ]
      )

    assert code =~ "fn get_bool<'a>"
    assert code =~ "fn get_i64<'a>"
    assert code =~ "fn get_string<'a>"
    assert code =~ "fn get_string_list<'a>"
    assert code =~ "fn get_term_list<'a>"
    assert code =~ "fn get_map<'a>"
    assert code =~ "value.decode::<Vec<String>>()"
    assert code =~ "value.is_map()"
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

    assert code =~ "rustler::resource! {"
    assert code =~ "Document, env,"
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

  test "builds resource handle boilerplate" do
    code =
      "__rq_items!();"
      |> RustQ.render!("resource_handle.rs",
        splice: [
          items:
            RustQ.Rustler.resource_handle(:EncodedImage,
              fields: [bytes: "Vec<u8>"],
              handle_field: :ref
            )
        ]
      )

    assert code =~ "struct EncodedImage"
    assert code =~ "pub bytes: Vec<u8>"
    assert code =~ "impl rustler::Resource for EncodedImage"
    assert code =~ "fn decode_encoded_image_handle<'a>"
    assert code =~ "term: Term<'a>"
    assert code =~ ~S/Atom::from_bytes(term.get_env(), b"ref")?/
    assert code =~ ".decode::<ResourceArc<EncodedImage>>()"
  end

  test "builds resource handles with custom decoder and field" do
    code =
      "__rq_items!();"
      |> RustQ.render!("resource_handle.rs",
        splice: [
          items:
            RustQ.Rustler.resource_handle(:Session,
              fields: [id: :u64],
              handle_field: "handle",
              decoder: :decode_session_ref
            )
        ]
      )

    assert code =~ "fn decode_session_ref<'a>"
    assert code =~ ~S/Atom::from_bytes(term.get_env(), b"handle")?/
    assert code =~ ".decode::<ResourceArc<Session>>()"
  end

  test "builds option struct decoders" do
    alias RustQ.Rust.AST.Builder, as: A
    alias RustQ.Rustler.Decode, as: R

    code =
      "__rq_items!();"
      |> RustQ.render!("opts.rs",
        splice: [
          items:
            RustQ.Rustler.opts_decoder(:RectOpts,
              lifetime: :a,
              fields: [
                x: [type: :f32, decode: R.opt_decode(:opt_f32, :opts, :x)],
                mode: [type: :Atom, decode: R.required_opt_decode(:opt_atom_option, :opts, :mode)],
                count: [
                  type: {:option, :i64},
                  decode: R.optional_term_decode(:opts, :count, :i64)
                ],
                fill: [
                  type: {:option, "Term<'a>"},
                  decode: A.call(:opt_term, [:opts, A.atom(:fill)])
                ]
              ]
            )
        ]
      )

    assert code =~ "pub struct RectOpts<'a>"
    assert code =~ "pub x: f32"
    assert code =~ "pub mode: Atom"
    assert code =~ "pub count: Option<i64>"
    assert code =~ "pub fill: Option<Term<'a>>"

    assert code =~
             "pub fn decode_rect_opts<'a>(opts: &[(Atom, Term<'a>)]) -> NifResult<RectOpts<'a>>"

    assert code =~ "x: opt_f32(opts, atoms::x())?"
    assert code =~ "mode: opt_atom_option(opts, atoms::mode())?.ok_or(rustler::Error::BadArg)?"
    assert code =~ "match opt_term(opts, atoms::count())"
    assert code =~ "Some(term) => Some(term.decode::<i64>()?)"
    assert code =~ "None => None"
    assert code =~ "fill: opt_term(opts, atoms::fill())"
    assert code =~ "_phantom: std::marker::PhantomData"
  end

  test "builds option struct decoders from Meta type fields" do
    code =
      "__rq_items!();"
      |> RustQ.render!("typed_opts.rs",
        splice: [
          items:
            RustQ.Rustler.opts_decoder(:TypedOpts,
              lifetime: :a,
              fields: [
                x: [type: RustQ.Spec.type(quote(do: RustQ.Type.f32())), required: true],
                mode: [type: RustQ.Spec.type(quote(do: RustQ.Type.enum(:mode))), required: true],
                label: [type: RustQ.Spec.type(quote(do: String.t()))],
                paint: [type: RustQ.Spec.type(quote(do: Skia.Paint.t()))]
              ]
            )
        ]
      )

    assert code =~ "pub x: f32"
    assert code =~ "pub mode: Atom"
    assert code =~ "pub label: Option<String>"
    assert code =~ "pub paint: Option<Term<'a>>"
    assert code =~ "x: opt_f32(opts, atoms::x())?"
    assert code =~ "mode: opt_atom_option(opts, atoms::mode())?.ok_or(rustler::Error::BadArg)?"
    assert code =~ "match opt_term(opts, atoms::label())"
    assert code =~ "Some(term) => Some(term.decode::<String>()?)"
    assert code =~ "paint: opt_term(opts, atoms::paint())"
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
