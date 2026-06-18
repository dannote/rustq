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

  test "builds a function AST from defrust valid Elixir" do
    defmodule GeneratedSaveCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec generated_save(R.ref(Canvas.t())) :: R.nif_result(R.unit())
      defrust generated_save(canvas) do
        canvas.save()
        :ok
      end
    end

    assert %AST.Function{name: :generated_save, body: [%AST.ExprStmt{}, %AST.Return{}]} =
             GeneratedSaveCase.__rustq_asts__() |> List.first()

    source = GeneratedSaveCase.__rustq_source__()
    assert source =~ "fn generated_save(canvas: &Canvas) -> NifResult<()>"
    assert source =~ "canvas.save();"
    assert source =~ "Ok(())"
  end

  test "defrust specs can use explicit Rust path and raw type markers" do
    defmodule ExplicitRustTypeCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec draw_oval_impl(
              R.ref(SkiaSafe.Canvas.t()),
              GeneratedOpts.OvalOpts.t(R.lifetime(:a)),
              R.slice({R.atom(), R.term()})
            ) :: R.nif_result(R.unit())
      defrust draw_oval_impl(canvas, opts, raw_opts) do
        rect = Rect.from_xywh(opts.x, opts.y, opts.width, opts.height)
        canvas.draw_oval(rect, ref(raw_opts))
        :ok
      end
    end

    source = ExplicitRustTypeCase.__rustq_source__()
    assert source =~ "fn draw_oval_impl<'a>("
    assert source =~ "canvas: &skia_safe::Canvas"
    assert source =~ "opts: generated_opts::OvalOpts<'a>"
    assert source =~ "raw_opts: &[(Atom, Term<'a>)]"
  end

  test "defrust infers mutable option pattern bindings from mut_ref usage" do
    defmodule MutableOptionPatternCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec apply_if_present(R.option(Paint.t())) :: R.nif_result(R.unit())
      defrust apply_if_present(maybe_paint) do
        case maybe_paint do
          {:some, paint} ->
            unwrap!(apply_blend_mode(mut_ref(paint), []))
            use_paint(ref(paint))

          :none ->
            :ok
        end

        :ok
      end
    end

    source = MutableOptionPatternCase.__rustq_source__()
    assert source =~ "Some(mut paint) =>"
    assert source =~ "apply_blend_mode(&mut paint"
  end

  test "defrust lowers arithmetic operators" do
    defmodule ArithmeticCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec scale(R.f32(), R.f32()) :: R.f32()
      defrust scale(x, y) do
        x + y * 2.0 - x / 4.0
      end
    end

    source = ArithmeticCase.__rustq_source__()
    assert source =~ "x + y * 2.0 - x / 4.0"
  end

  test "defrust lowers Elixir pipelines to Rust method, operator, and cast chains" do
    defmodule PipelineCastCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec alpha(OpacityOpts.t()) :: R.u8()
      defrust alpha(opts) do
        opts.opacity.unwrap_or(1.0)
        |> clamp(0.0, 1.0)
        |> Kernel.*(255.0)
        |> round()
        |> cast(:u8)
      end
    end

    source = PipelineCastCase.__rustq_source__()
    assert source =~ "opts.opacity.unwrap_or(1.0).clamp(0.0, 1.0)"
    assert source =~ "* 255.0"
    assert source =~ ".round() as u8"
  end

  test "defrust cast accepts RustQ type markers" do
    defmodule TypeMarkerCastCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec widen(R.u8()) :: R.u32()
      defrust widen(value) do
        cast(value, R.u32())
      end
    end

    source = TypeMarkerCastCase.__rustq_source__()
    assert source =~ "value as u32"
  end

  test "defrust lowers comparison operators" do
    defmodule ComparisonCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec positive(R.f32()) :: R.nif_result(R.unit())
      defrust positive(radius) do
        if radius > 0.0 do
          use_positive(radius)
        else
          use_zero()
        end

        :ok
      end
    end

    source = ComparisonCase.__rustq_source__()
    assert source =~ "if radius > 0.0"
  end

  test "defrust expands ordinary Elixir helper macros before lowering" do
    defmodule MacroBodyCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      defmacro with_saved_canvas(do: body) do
        quote do
          var!(canvas).save()
          unquote(body)
          var!(canvas).restore()
        end
      end

      @spec draw(R.ref(Canvas.t())) :: R.nif_result(R.unit())
      defrust draw(canvas) do
        with_saved_canvas do
          canvas.translate({1.0, 2.0})
        end

        :ok
      end
    end

    source = MacroBodyCase.__rustq_source__()
    assert source =~ "canvas.save();"
    assert source =~ "canvas.translate((1.0, 2.0));"
    assert source =~ "canvas.restore();"
  end

  test "defrustmod maps alias calls to Rust module paths" do
    defmodule ModuleMappedCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      defrustmod(GeneratedOpts, as: :generated_opts)

      @spec decode(term()) :: R.nif_result(R.unit())
      defrust decode(opts) do
        GeneratedOpts.decode_path_opts(ref(opts))
      end
    end

    source = ModuleMappedCase.__rustq_source__()
    assert source =~ "generated_opts::decode_path_opts(&opts)"
  end

  test "defrustmod groups nested defrust declarations" do
    defmodule NestedModuleCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      defrustmod GeneratedHelpers, as: :generated_helpers do
        @spec save(R.ref(Canvas.t())) :: R.nif_result(R.unit())
        defrust save(canvas) do
          canvas.save()
          :ok
        end
      end
    end

    source = NestedModuleCase.__rustq_source__()
    assert source =~ "mod generated_helpers"
    assert source =~ "fn save(canvas: &Canvas) -> NifResult<()>"
    assert source =~ "canvas.save();"
  end

  test "lowers plural module alias calls as snake_case Rust modules" do
    defmodule AutomaticModuleAliasCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec atom_call() :: R.nif_result(atom())
      defrust atom_call() do
        Atoms.fill()
      end
    end

    source = AutomaticModuleAliasCase.__rustq_source__()
    assert source =~ "atoms::fill()"
  end

  test "lowers zero-arity alias calls from defrust as Rust calls" do
    defmodule AliasCallCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec atom_call() :: R.nif_result(atom())
      defrust atom_call() do
        Atoms.args()
      end
    end

    source = AliasCallCase.__rustq_source__()
    assert source =~ "atoms::args()"
  end

  test "builds typed Rustler decode expressions from defrust valid Elixir" do
    defmodule DecodeTermsCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode_terms(term()) :: R.nif_result(R.vec(term()))
      defrust decode_terms(term) do
        decode_as!(term, R.vec(term()))
      end
    end

    source = DecodeTermsCase.__rustq_source__()
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
