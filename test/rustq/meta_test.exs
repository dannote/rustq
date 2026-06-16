defmodule RustQ.MetaTest do
  use ExUnit.Case, async: true

  defmodule Generated do
    use RustQ.Meta

    alias RustQ.Type, as: R

    @type mode :: :src_over | :multiply

    @type event :: {:click, String.t()} | {:resize, R.u32(), R.u32()}

    @type rect_opts :: %{
            required(:x) => R.f32(),
            required(:y) => R.f32(),
            required(:width) => R.f32(),
            required(:height) => R.f32(),
            optional(:fill) => term()
          }

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

    @spec draw_rect(R.ref(Canvas.t()), rect_opts(), term()) :: R.nif_result(R.unit())
    defrust draw_rect(canvas, opts, raw_opts) do
      rect = Rect.from_xywh(opts.x, opts.y, opts.width, opts.height)
      paint = unwrap!(decode_paint(opts.fill))
      unwrap!(apply_blend_mode(mut_ref(paint), raw_opts))
      canvas.draw_rect(ref(rect), ref(paint))
      :ok
    end

    @spec maybe_save(R.option(R.ref(Canvas.t()))) :: R.nif_result(R.unit())
    defrust maybe_save(canvas) do
      case canvas do
        nil -> :ok
        canvas -> canvas.save()
      end

      :ok
    end

    @spec unwrap_code(R.result(R.u32(), atom())) :: R.nif_result(R.u32())
    defrust unwrap_code(result) do
      case result do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, reason}
      end
    end

    @spec handle_event(event()) :: R.nif_result(R.unit())
    defrust handle_event(event) do
      case event do
        {:click, name} -> log_click(name)
        {:resize, width, height} -> log_resize(width, height)
      end

      :ok
    end
  end

  test "generates Rust source from defrust functions and specs" do
    source = Generated.__rustq_source__()

    assert source =~ "fn draw_save(canvas: &Canvas) -> NifResult<()>"
    assert source =~ "canvas.save();"
    assert source =~ "Ok(())"

    assert source =~ "pub enum Mode"
    assert source =~ "SrcOver,"
    assert source =~ "pub fn decode_mode_atom(value: Atom) -> NifResult<Mode>"
    assert source =~ "fn decode_mode(atom: Atom) -> NifResult<Mode>"
    assert source =~ "match atom"
    assert source =~ "value if value == atoms::src_over() =>"
    assert source =~ "Ok(BlendMode::SrcOver)"
    assert source =~ ~s|Err(rustler::Error::RaiseAtom("invalid_blend_mode"))|

    assert source =~ "pub enum Event"
    assert source =~ "Click(String),"
    assert source =~ "Resize(u32, u32),"
    assert source =~ "pub fn decode_event<'a>(term: Term<'a>) -> NifResult<Event>"
    assert source =~ "todo!()"
    assert source =~ "pub struct RectOpts"
    assert source =~ "pub x: f32,"
    assert source =~ "pub fill: Option<Term<'a>>,"
    assert source =~ "pub fn decode_rect_opts<'a>(term: Term<'a>) -> NifResult<RectOpts<'a>>"
    assert source =~ "decode_required(term, atoms::x())?"
    assert source =~ "decode_optional(term, atoms::fill())?"
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
    assert source =~ "Event::Click(name) =>"
    assert source =~ "Event::Resize(width, height) =>"
    assert RustQ.valid?(source, "generated_defrust.rs")
  end

  test "set-theoretic type aliases are available to specs" do
    assert %RustQ.Meta.Type{kind: :enum, rust: "Mode", meta: %{variants: [:src_over, :multiply]}} =
             Generated.__rustq_types__()[{:mode, 0}]

    assert Generated.__rustq_source__() =~ "pub enum Mode"

    assert %RustQ.Meta.Type{kind: :tuple_enum, rust: "Event", meta: %{variants: event_variants}} =
             Generated.__rustq_types__()[{:event, 0}]

    assert {:click, [%RustQ.Meta.Type{rust: "String"}]} = List.keyfind(event_variants, :click, 0)

    assert {:resize, [%RustQ.Meta.Type{rust: "u32"}, %RustQ.Meta.Type{rust: "u32"}]} =
             List.keyfind(event_variants, :resize, 0)

    assert %RustQ.Meta.Type{
             kind: :struct,
             rust: "RectOpts<'a>",
             ast: %RustQ.Rust.AST.TypePath{parts: ["RectOpts"], lifetimes: [:a]},
             meta: %{fields: fields}
           } = Generated.__rustq_types__()[{:rect_opts, 0}]

    assert Enum.any?(fields, &match?({:x, %RustQ.Meta.Type{rust: "f32"}, :required}, &1))
    assert Enum.any?(fields, &match?({:fill, %RustQ.Meta.Type{rust: "Term<'a>"}, :optional}, &1))

    assert Generated.__rustq_source__() =~
             "pub fn decode_mode_atom(value: Atom) -> NifResult<Mode>"

    assert Generated.__rustq_source__() =~ "fn decode_mode(atom: Atom) -> NifResult<Mode>"
  end

  test "generated ASTs are retained before fragment validation" do
    [draw_save, decode_mode, draw_rect, maybe_save | _] = Generated.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{name: :draw_save, args: [canvas: %RustQ.Rust.AST.TypeRef{}]} =
             draw_save

    assert %RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}} = hd(decode_mode.body)

    assert %RustQ.Rust.AST.Function{
             args: [_canvas_arg, {:opts, %RustQ.Rust.AST.TypePath{}}, _raw_opts_arg]
           } = draw_rect

    assert %RustQ.Rust.AST.Let{pattern: %RustQ.Rust.AST.PatVar{name: :rect}} = hd(draw_rect.body)

    assert Enum.any?(
             draw_rect.body,
             &match?(
               %RustQ.Rust.AST.Let{pattern: %RustQ.Rust.AST.PatVar{name: :paint}, mutable: true},
               &1
             )
           )

    assert %RustQ.Rust.AST.ExprStmt{
             expr: %RustQ.Rust.AST.Match{
               arms: [
                 %RustQ.Rust.AST.Arm{pattern: %RustQ.Rust.AST.PatNone{}},
                 %RustQ.Rust.AST.Arm{pattern: %RustQ.Rust.AST.PatSome{}}
               ]
             }
           } = hd(maybe_save.body)
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
