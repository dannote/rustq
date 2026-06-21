Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.DefrustTest do
  use ExUnit.Case, async: true

  alias RustQ.Diagnostic
  alias RustQ.Meta.AST, as: MetaAST
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

  test "defrust uses module specs as callable metadata for propagation inference" do
    defmodule LocalCallablePropagationCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode(atom()) :: R.nif_result(R.u32())
      defrust decode(atom) do
        case atom do
          :ok -> {:ok, 1}
          _ -> {:error, :badarg}
        end
      end

      @spec consume(R.u32()) :: R.nif_result(R.unit())
      defrust consume(value) do
        _copy = value
        :ok
      end

      @spec argument(atom()) :: R.nif_result(R.unit())
      defrust argument(atom) do
        consume(decode(atom))
        :ok
      end
    end

    source = LocalCallablePropagationCase.__rustq_source__()

    assert source =~ "consume(decode(atom)?)"
    assert RustQ.valid?(source, "local_callable_propagation.rs")
  end

  defmodule SynSourceDomain do
    defmacro __using__(_opts) do
      quote do
        use RustQ.Meta, rust_sources: ["test/fixtures/external_callables.rs"]
      end
    end
  end

  test "defrust can use Syn-derived external callable metadata" do
    defmodule SynExternalCallableCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/external_callables.rs"]

      alias RustQ.Type, as: R

      @spec decode_color(R.term()) :: R.nif_result(R.path(:Color))
      defrust decode_color(term) do
        color = decode_as!(term, R.u32())
        {:ok, Color.from_argb(255, 0, 0, color)}
      end

      @spec draw(R.term(), R.slice({R.atom(), R.term()})) :: R.nif_result(R.unit())
      defrust draw(term, opts) do
        unwrap!(stroke_paint(decode_color(term), 1.0, opts))
        :ok
      end
    end

    source = SynExternalCallableCase.__rustq_source__()

    assert source =~ "stroke_paint(decode_color(term)?, 1.0, opts)?;"
    assert RustQ.valid?(source, "syn_external_callable.rs")
  end

  test "defrust can use Syn-derived external method metadata" do
    defmodule SynExternalMethodCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/external_methods.rs"]

      alias RustQ.Type, as: R

      @spec decode_blend_mode(R.atom()) :: R.nif_result(R.path(:BlendMode))
      defrust decode_blend_mode(atom) do
        case atom do
          :src_over -> {:ok, BlendMode.SrcOver}
          _ -> {:error, :badarg}
        end
      end

      @spec apply(R.mut_ref(Paint.t()), R.atom()) :: R.nif_result(R.unit())
      defrust apply(paint, atom) do
        paint.set_blend_mode(decode_blend_mode(atom))
        :ok
      end
    end

    source = SynExternalMethodCase.__rustq_source__()

    assert source =~ "paint.set_blend_mode(decode_blend_mode(atom)?);"
    assert RustQ.valid?(source, "syn_external_method.rs")
  end

  test "defrust can use callable metadata from other RustQ modules" do
    defmodule CallableProducerCase do
      use RustQ.Meta

      alias RustQ.Type, as: R

      @spec decode_color(R.term()) :: R.nif_result(R.path(:Color))
      defrust decode_color(term) do
        color = decode_as!(term, R.u32())
        {:ok, Color.from_argb(255, 0, 0, color)}
      end
    end

    defmodule CallableConsumerCase do
      use RustQ.Meta,
        rust_sources: ["test/fixtures/external_callables.rs"],
        callable_modules: [CallableProducerCase]

      alias RustQ.Type, as: R

      @spec draw(R.term(), R.slice({R.atom(), R.term()})) :: R.nif_result(R.unit())
      defrust draw(term, opts) do
        unwrap!(stroke_paint(decode_color(term), 1.0, opts))
        :ok
      end
    end

    source = CallableConsumerCase.__rustq_source__()

    assert source =~ "stroke_paint(decode_color(term)?, 1.0, opts)?;"
    assert RustQ.valid?(source, "module_callable_consumer.rs")
  end

  test "defrust can use Syn-derived external callable metadata through wrapper macros" do
    defmodule SynExternalCallableWrapperCase do
      use SynSourceDomain

      alias RustQ.Type, as: R

      @spec decode_color(R.term()) :: R.nif_result(R.path(:Color))
      defrust decode_color(term) do
        color = decode_as!(term, R.u32())
        {:ok, Color.from_argb(255, 0, 0, color)}
      end

      @spec draw(R.term(), R.slice({R.atom(), R.term()})) :: R.nif_result(R.unit())
      defrust draw(term, opts) do
        unwrap!(stroke_paint(decode_color(term), 1.0, opts))
        :ok
      end
    end

    source = SynExternalCallableWrapperCase.__rustq_source__()

    assert source =~ "stroke_paint(decode_color(term)?, 1.0, opts)?;"
    assert RustQ.valid?(source, "syn_external_callable_wrapper.rs")
  end

  test "configured callable modules must expose callable metadata" do
    assert_raise ArgumentError, ~r/does not expose __rustq_callables__\/0/, fn ->
      defmodule InvalidCallableModuleConfigCase do
        use RustQ.Meta, callable_modules: [String]
        alias RustQ.Type, as: R

        @spec run() :: R.nif_result(R.unit())
        defrust run do
          :ok
        end
      end
    end
  end

  test "defrust build failures include boundary diagnostic context" do
    error =
      assert_raise Diagnostic.Error, fn ->
        defmodule InvalidDefrustBoundaryCase do
          use RustQ.Meta
          alias RustQ.Type, as: R

          @spec invalid(term()) :: R.nif_result(R.unit())
          defrust invalid(term) do
            %{value: value} = term
            value
          end
        end
      end

    diagnostic = error.diagnostic

    assert diagnostic.phase == :defrust
    assert diagnostic.kind == :build_failed
    assert diagnostic.snippet =~ "%{value: value} = term"
    assert diagnostic.details.function == :invalid
    assert diagnostic.details.arity == 1

    assert %Diagnostic{phase: :lower, kind: :unsupported_binding_pattern} =
             diagnostic.details.cause
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

  test "defrust infers mutable let bindings from statement method calls" do
    defmodule MutableMethodReceiverCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec build() :: R.nif_result(R.unit())
      defrust build() do
        builder = PathBuilder.new()
        builder.add_circle(Point.new(0.0, 0.0), 1.0, none())
        use_path(builder.detach())

        :ok
      end
    end

    source = MutableMethodReceiverCase.__rustq_source__()
    assert source =~ "let mut builder = PathBuilder::new();"
    assert source =~ "builder.add_circle(Point::new(0.0, 0.0), 1.0, None);"
  end

  test "Meta returns rendered items" do
    item = MetaAST.item(RustQ.Meta.GeneratedCase, :draw_save)

    assert RustQ.Rust.to_fragment(item) =~ "fn draw_save"

    assert_raise ArgumentError, fn ->
      MetaAST.item(RustQ.Meta.GeneratedCase, :missing)
    end
  end

  test "defrust lowers zero-arity closures" do
    defmodule ZeroArityClosureCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec value() :: R.i64()
      defrust value() do
        get_or_init(fn -> 42 end)
      end
    end

    source = ZeroArityClosureCase.__rustq_source__()
    assert source =~ "get_or_init(|| 42)"
  end

  test "defrust lowers arrays and indexed assignment" do
    defmodule ArrayIndexCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec fill(R.u8()) :: R.nif_result(R.unit())
      defrust fill(value) do
        values = array([cast(0, :u8), cast(0, :u8)])
        index = cast(0, :usize)
        assign!(index(values, index), value)
        :ok
      end
    end

    source = ArrayIndexCase.__rustq_source__()
    assert source =~ "let mut values = [0 as u8, 0 as u8];"
    assert source =~ "values[index] = value;"
  end

  test "defrust lowers structural Rust struct literals" do
    defmodule StructLiteralCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec cubic(R.f64(), R.f64()) :: R.path(:CubicResampler)
      defrust cubic(b, c) do
        struct_literal(CubicResampler, b: cast(b, :f32), c: cast(c, :f32))
      end
    end

    source = StructLiteralCase.__rustq_source__()
    assert source =~ "CubicResampler {"
    assert source =~ "b: b as f32"
    assert source =~ "c: c as f32"
  end

  test "defrust lowers bitwise helper calls" do
    defmodule BitwiseHelperCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec red(R.u32()) :: R.u8()
      defrust red(rgba) do
        Bitwise.band(Bitwise.bsr(rgba, 24), 0xFF)
        |> cast(:u8)
      end
    end

    source = BitwiseHelperCase.__rustq_source__()
    assert source =~ "(rgba >> 24 & 255) as u8"
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

  test "defrustmod maps nested alias constant paths" do
    defmodule NestedModuleConstantCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      defrustmod(SkiaSafe.ArcSize, as: [:skia_safe, :path_builder, :ArcSize])

      @spec large() :: R.nif_result(R.path(:ArcSize))
      defrust large() do
        {:ok, SkiaSafe.ArcSize.Large}
      end
    end

    source = NestedModuleConstantCase.__rustq_source__()

    assert source =~ "Ok(skia_safe::path_builder::ArcSize::Large)"
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

      @spec nil_atom_call() :: R.nif_result(atom())
      defrust nil_atom_call() do
        Atoms.nil()
      end
    end

    source = AliasCallCase.__rustq_source__()
    assert source =~ "atoms::args()"
    assert source =~ "atoms::nil()"
  end

  test "lowers simple for comprehensions to Rust for loops" do
    defmodule ForComprehensionCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec push_pairs(R.vec({String.t(), R.u32()})) :: R.nif_result(R.unit())
      defrust push_pairs(pairs) do
        for {name, count} <- pairs do
          push_pair(name, count)
        end

        :ok
      end
    end

    source = ForComprehensionCase.__rustq_source__()

    assert source =~ "for (name, count) in pairs"
    assert source =~ "push_pair(name, count);"
  end

  test "marks mutable lets inside if branches" do
    defmodule IfBranchMutationCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec collect_if(R.bool(), R.vec(R.f64())) :: R.nif_result(R.unit())
      defrust collect_if(enabled, values) do
        if enabled do
          mapped = Vec.with_capacity(values.len())

          for value <- values do
            mapped.push(cast(value, :f32))
          end

          use_values(mapped.as_slice())
        end

        :ok
      end
    end

    source = IfBranchMutationCase.__rustq_source__()
    assert source =~ "let mut mapped = Vec::with_capacity(values.len());"
  end

  test "keeps tuple pattern lets through mutability inference" do
    defmodule TupleLetCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec pair(term()) :: R.nif_result(R.unit())
      defrust pair(term) do
        {left, right} = decode_as!(term, {R.u8(), R.u8()})
        use_pair(left, right)
        :ok
      end
    end

    source = TupleLetCase.__rustq_source__()
    assert source =~ "let (left, right) = term.decode::<(u8, u8)>()?;"
  end

  test "marks assign bang targets as mutable lets" do
    defmodule AssignBangMutationCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec toggle() :: R.nif_result(R.bool())
      defrust toggle() do
        flag = true
        assign!(flag, false)
        {:ok, flag}
      end
    end

    source = AssignBangMutationCase.__rustq_source__()
    assert source =~ "let mut flag = true;"
    assert source =~ "flag = false;"
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

  test "lowers integer match patterns from defrust valid Elixir" do
    defmodule IntegerMatchCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode(R.i64()) :: R.nif_result(R.unit())
      defrust decode(op) do
        case op do
          1 -> draw_move()
          2 -> draw_line()
          _ -> :ok
        end

        :ok
      end
    end

    source = IntegerMatchCase.__rustq_source__()

    assert source =~ "1i64 =>"
    assert source =~ "2i64 =>"
  end

  test "lowers Rust tuple field access from defrust valid Elixir" do
    defmodule TupleFieldCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec first(R.raw(:Tuple1)) :: R.nif_result(R.i64())
      defrust first(tuple) do
        {:ok, tuple_field(tuple, 0)}
      end
    end

    source = TupleFieldCase.__rustq_source__()

    assert source =~ "Ok(tuple.0)"
  end

  test "lowers nested tuple decode probe matches" do
    defmodule NestedTupleDecodeProbeCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec probe(term()) :: R.nif_result(R.unit())
      defrust probe(term) do
        case decode_as(term, {R.atom(), {R.f64(), R.f64()}}) do
          {:ok, {tag, {x, y}}} -> handle(tag, x, y)
          {:error, _reason} -> :ok
        end

        :ok
      end
    end

    source = NestedTupleDecodeProbeCase.__rustq_source__()
    assert source =~ "Ok((tag, (x, y))) =>"
  end

  test "builds typed Rustler decode result probes from defrust valid Elixir" do
    defmodule DecodeResultProbeCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec probe(term()) :: R.nif_result(R.unit())
      defrust probe(term) do
        case decode_as(term, {R.i64(), R.f64()}) do
          {:ok, {op, value}} -> handle(op, value)
          {:error, _reason} -> :ok
        end

        :ok
      end
    end

    source = DecodeResultProbeCase.__rustq_source__()

    assert source =~ "match term.decode::<(i64, f64)>()"
    assert source =~ "Ok((op, value)) =>"
    assert source =~ "Err(_reason) =>"
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
