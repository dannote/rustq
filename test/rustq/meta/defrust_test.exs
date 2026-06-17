Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.DefrustTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.GeneratedCase, as: Generated
  alias RustQ.Rust.AST

  test "generates Rust source from defrust functions and specs" do
    source = Generated.__rustq_source__()

    assert source =~ "fn draw_save(canvas: &Canvas) -> NifResult<()>"
    assert source =~ "canvas.save();"
    assert source =~ "Ok(())"

    assert source =~ "fn decode_mode(atom: Atom) -> NifResult<Mode>"
    assert source =~ "match atom"
    assert source =~ "value if value == atoms::src_over() =>"
    assert source =~ "Ok(BlendMode::SrcOver)"
    assert source =~ ~s|Err(rustler::Error::RaiseAtom("invalid_blend_mode"))|

    assert source =~ "fn draw_rect<'a>("
    assert source =~ "opts: RectOpts<'a>"
    assert source =~ "raw_opts: Term<'a>"
    assert source =~ "let rect = Rect::from_xywh(opts.x, opts.y, opts.width, opts.height);"
    assert source =~ "let mut paint = decode_paint(opts.fill)?;"
    assert source =~ "apply_blend_mode(&mut paint, raw_opts)?;"
    assert source =~ "canvas.draw_rect(&rect, &paint);"

    assert source =~ "fn maybe_save(canvas: Option<&Canvas>) -> NifResult<()>"
    assert source =~ "None => {}"
    assert source =~ "Some(canvas) => {"

    assert source =~ "fn unwrap_code(result: Result<u32, Atom>) -> NifResult<u32>"
    assert source =~ "Ok(value) =>"
    assert source =~ "Err(reason) =>"

    assert source =~ "fn handle_event(event: Event) -> NifResult<()>"
    assert source =~ "Event::Click(Click { name: name }) =>"
    assert source =~ "Event::Resize(Resize { width: width, height: height }) =>"

    assert RustQ.valid?(source, "generated_defrust.rs")
  end

  test "builds a function AST from quoted valid Elixir" do
    function =
      RustQ.Meta.function_ast(
        :generated_save,
        [canvas: quote(do: RustQ.Type.ref(Canvas.t()))],
        quote(do: RustQ.Type.nif_result(RustQ.Type.unit())),
        quote do
          canvas.save()
          :ok
        end
      )

    assert %AST.Function{name: :generated_save, body: [%AST.ExprStmt{}, %AST.Return{}]} = function

    source = RustQ.Rust.AST.Render.render_function_native(function)
    assert source =~ "fn generated_save(canvas: &Canvas) -> NifResult<()>"
    assert source =~ "canvas.save();"
    assert source =~ "Ok(())"
  end

  test "builds typed Rustler decode expressions from valid Elixir" do
    function =
      RustQ.Meta.function_ast(
        :decode_terms,
        [term: quote(do: term())],
        quote(do: RustQ.Type.nif_result(RustQ.Type.vec(term()))),
        quote do
          decode_as!(term, RustQ.Type.vec(term()))
        end
      )

    source = RustQ.Rust.AST.Render.render_function_native(function)
    assert source =~ "fn decode_terms<'a>(term: Term<'a>) -> NifResult<Vec<Term<'a>>>"
    assert source =~ "term.decode::<Vec<Term<'a>>>()?"
  end

  test "native AST renderer emits Rust through syn" do
    [draw_save | _] = Generated.__rustq_asts__()

    assert RustQ.Native.render_ast(draw_save) =~ "fn draw_save(canvas: &Canvas) -> NifResult<()>"
    assert RustQ.Native.render_ast(draw_save) =~ "canvas.save();"
  end

  test "generated items are validated Rust fragments" do
    assert Enum.all?(Generated.__rustq_items__(), &match?(%RustQ.Rust.Fragment{kind: :item}, &1))
  end
end
