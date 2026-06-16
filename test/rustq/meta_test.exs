defmodule RustQ.MetaTest do
  use ExUnit.Case, async: true

  defmodule Generated do
    use RustQ.Meta

    alias RustQ.Type, as: R

    @type mode :: :src_over | :multiply

    @spec draw_save(R.ref(Canvas.t())) :: R.nif_result(R.unit())
    defrust draw_save(canvas) do
      canvas.save()
      :ok
    end

    @spec decode_mode(atom()) :: R.nif_result(mode())
    defrust decode_mode(atom) do
      case atom do
        :src_over -> {:ok, BlendMode.SrcOver}
        :multiply -> {:ok, BlendMode.Multiply}
        _ -> {:error, :invalid_blend_mode}
      end
    end

    @spec draw_rect(R.ref(Canvas.t()), RectOpts.t(), R.term()) :: R.nif_result(R.unit())
    defrust draw_rect(canvas, opts, raw_opts) do
      rect = Rect.from_xywh(opts.x, opts.y, opts.width, opts.height)
      paint = unwrap!(decode_paint(opts.fill))
      unwrap!(apply_blend_mode(mut_ref(paint), raw_opts))
      canvas.draw_rect(ref(rect), ref(paint))
      :ok
    end
  end

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
    assert source =~ "opts: RectOpts"
    assert source =~ "raw_opts: Term<'a>"
    assert source =~ "let rect = Rect::from_xywh(opts.x, opts.y, opts.width, opts.height);"
    assert source =~ "let mut paint = decode_paint(opts.fill)?;"
    assert source =~ "apply_blend_mode(&mut paint, raw_opts)?;"
    assert source =~ "canvas.draw_rect(&rect, &paint);"
  end

  test "set-theoretic type aliases are available to specs" do
    assert %RustQ.Meta.Type{kind: :enum, rust: "Mode", meta: %{variants: [:src_over, :multiply]}} =
             Generated.__rustq_types__()[{:mode, 0}]

    assert Generated.__rustq_source__() =~ "fn decode_mode(atom: Atom) -> NifResult<Mode>"
  end

  test "generated ASTs are retained before fragment validation" do
    [draw_save, decode_mode, draw_rect] = Generated.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{name: :draw_save} = draw_save
    assert %RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}} = hd(decode_mode.body)
    assert %RustQ.Rust.AST.Let{pattern: %RustQ.Rust.AST.PatVar{name: :rect}} = hd(draw_rect.body)

    assert Enum.any?(
             draw_rect.body,
             &match?(
               %RustQ.Rust.AST.Let{pattern: %RustQ.Rust.AST.PatVar{name: :paint}, mutable: true},
               &1
             )
           )
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
