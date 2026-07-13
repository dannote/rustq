Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.DefrustTest do
  use ExUnit.Case, async: true

  alias RustQ.Diagnostic
  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Meta.GeneratedCase, as: Generated
  alias RustQ.Native.Nif
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

  test "preserves no-parentheses function pointer field access in expected positions" do
    defmodule FunctionPointerFieldCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/function_pointer_field.rs"]
      alias RustQ.Type, as: R

      @spec decode_function(R.path(:DecodeField)) :: R.path(:DecodeFn)
      defrust(decode_function(field), do: field.decode)
    end

    source = FunctionPointerFieldCase.__rustq_source__()

    assert source =~ "fn decode_function(field: DecodeField) -> DecodeFn"
    assert source =~ "field.decode"
    refute source =~ "field.decode::<DecodeFn>()"
  end

  test "selects map-backed type structs with boundary derives" do
    code =
      "__rq_items!();"
      |> RustQ.render!("type_structs.rs",
        splice: [
          items:
            MetaAST.struct_type_items(Generated, [:rect_opts],
              derive: [:Clone, :Debug, "rustler::NifMap"],
              field_vis: nil
            )
        ]
      )

    assert code =~ "#[derive(Clone, Debug, rustler::NifMap)]"
    assert code =~ "pub struct RectOpts"
    assert code =~ "width: f32"
    refute code =~ "pub width: f32"
    refute code =~ "fn decode_rect_opts"
  end

  test "propagates nested result tuple binding types into conditions" do
    defmodule ResultTupleBindingCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec enabled(term()) :: R.nif_result(R.u32())
      defrust enabled(term) do
        case decode_as(term, {atom(), R.vec(R.f64()), R.bool()}) do
          {:ok, {_tag, _values, flag}} ->
            flag =
              if flag do
                1
              else
                0
              end

            {:ok, flag}

          {:error, _reason} ->
            {:ok, 0}
        end
      end
    end

    source = ResultTupleBindingCase.__rustq_source__()

    assert source =~ "if flag {"
    refute source =~ "if flag? {"
  end

  test "defrust lowers macro-generated case clauses" do
    defmodule MacroGeneratedCaseClauseCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      defmacro generated_case(value) do
        clauses =
          quote do
            1 -> {:ok, 10}
            other -> {:ok, other}
          end

        quote do
          case unquote(value) do
            (unquote_splicing(clauses))
          end
        end
      end

      @spec decode(R.i64()) :: R.nif_result(R.i64())
      defrust decode(value) do
        generated_case(value)
      end
    end

    source = MacroGeneratedCaseClauseCase.__rustq_source__()

    assert source =~ "match value"
    assert source =~ "1 => Ok(10)"
    assert source =~ "other => Ok(other)"
    assert RustQ.valid?(source, "macro_generated_case_clause.rs")
  end

  test "defrustmacro defines Rust macros from Rusty-Elixir bodies" do
    defmodule DefrustMacroFieldCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec required_field(R.term(), binary()) :: R.nif_result(R.term())
      defrust required_field(term, _name) do
        {:ok, term}
      end

      defrustmacro field(term, name, type: :ty) do
        decode_as!(required_field(term, name), type)
      end

      @spec decode(R.term()) :: R.nif_result(R.u32())
      defrust decode(term) do
        field!(term, "value", R.u32())
      end
    end

    source = DefrustMacroFieldCase.__rustq_source__()

    assert source =~ "macro_rules! field"
    assert source =~ "$term:expr"
    assert source =~ "$type:ty"
    assert source =~ "required_field($term, $name)?.decode::<$type>()?"
    assert source =~ ~s|field!(term, "value", u32)|
    assert RustQ.valid?(source, "defrustmacro_field.rs")
  end

  test "defrustmacro can emit item macros from inner defrust bodies and repeat groups" do
    defmodule DefrustMacroItemCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type field :: %{
              required(:id) => R.u32(),
              required(:name) => R.raw(:"&'static str"),
              required(:repeated) => R.bool(),
              required(:decode) => R.raw(:"fn()")
            }

      @spec build_fields(R.slice(R.path(:Field))) :: R.nif_result(R.unit())
      defrust build_fields(_fields) do
        :ok
      end

      defrustmacro descriptor(
                     fn: name(:ident),
                     fields:
                       repeat do
                         field_id(:literal)
                         field_name(:literal)
                         field_mode(:ident)
                         field_decode(:ident)
                       end
                   ) do
        @spec name() :: R.nif_result(R.unit())
        defrust name() do
          build_fields(
            ref(
              array([
                repeat fields do
                  struct_literal(Field,
                    id: field_id,
                    name: field_name,
                    repeated: repeated!(field_mode),
                    decode: field_decode
                  )
                end
              ])
            )
          )
        end
      end
    end

    source = DefrustMacroItemCase.__rustq_source__()

    assert source =~ "macro_rules! descriptor"
    assert source =~ "fn $name:ident;"
    assert source =~ "fields [$("
    assert source =~ "$field_id:literal => $field_name:literal:"
    assert source =~ "fn $name() -> NifResult<()>"

    assert source =~
             "build_fields(&[$(Field { id: $field_id, name: $field_name, repeated: repeated!($field_mode), decode: $field_decode },)*])"

    assert RustQ.valid?(source, "defrustmacro_item.rs")
  end

  test "defrustmacro supports shared sparse skip descriptor field rows" do
    defmodule DefrustMacroSharedSkipFieldCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type field :: %{
              required(:id) => R.u32(),
              required(:name) => R.raw(:"&'static str"),
              required(:repeated) => R.bool(),
              required(:decode) => R.raw(:"fn()"),
              required(:skip_repeated) => R.bool(),
              required(:skip_bytes) => R.bool(),
              required(:skip) => R.raw(:"fn()")
            }

      @spec build_fields(R.slice(R.path(:Field))) :: R.nif_result(R.unit())
      defrust build_fields(_fields) do
        :ok
      end

      defrustmacro descriptor(
                     fn: name(:ident),
                     fields:
                       repeat do
                         field_id(:literal)
                         field_name(:literal)
                         field_mode(:ident)
                         field_decode(:ident)
                         skip_repeated(:literal)
                         skip_bytes(:literal)
                         field_skip(:ident)
                       end
                   ) do
        @spec name() :: R.nif_result(R.unit())
        defrust name() do
          build_fields(
            ref(
              array([
                repeat fields do
                  struct_literal(Field,
                    id: field_id,
                    name: field_name,
                    repeated: repeated!(field_mode),
                    decode: field_decode,
                    skip_repeated: skip_repeated,
                    skip_bytes: skip_bytes,
                    skip: field_skip
                  )
                end
              ])
            )
          )
        end
      end
    end

    source = DefrustMacroSharedSkipFieldCase.__rustq_source__()

    assert source =~
             "fields [$(" <>
               "$field_id:literal => $field_name:literal: $field_mode:ident $field_decode:ident; " <>
               "$skip_repeated:literal $skip_bytes:literal $field_skip:ident;)*]"

    assert RustQ.valid?(source, "defrustmacro_shared_skip_field.rs")
  end

  test "defrustmacro supports skip field descriptor rows" do
    defmodule DefrustMacroSkipFieldCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type skip_field :: %{
              required(:id) => R.u32(),
              required(:repeated) => R.bool(),
              required(:bytes) => R.bool(),
              required(:skip) => R.raw(:SkipFn)
            }

      @spec build_fields(R.slice(R.path(:SkipField))) :: R.nif_result(R.unit())
      defrust build_fields(_fields) do
        :ok
      end

      defrustmacro descriptor(
                     fn: name(:ident),
                     skip_fields:
                       repeat do
                         field_id(:literal)
                         field_repeated(:literal)
                         field_bytes(:literal)
                         field_skip(:ident)
                       end
                   ) do
        @spec name() :: R.nif_result(R.unit())
        defrust name() do
          build_fields(
            ref(
              array([
                repeat skip_fields do
                  struct_literal(SkipField,
                    id: field_id,
                    repeated: field_repeated,
                    bytes: field_bytes,
                    skip: field_skip
                  )
                end
              ])
            )
          )
        end
      end
    end

    source = DefrustMacroSkipFieldCase.__rustq_source__()

    assert source =~
             "skip_fields [$(" <>
               "$field_id:literal => $field_repeated:literal $field_bytes:literal $field_skip:ident;)*]"

    assert RustQ.valid?(source, "defrustmacro_skip_field.rs")
  end

  test "builds semantic item macro calls from defrustmacro metadata" do
    defmodule DefrustMacroItemCallCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type field :: %{
              required(:id) => R.u32(),
              required(:repeated) => R.bool(),
              required(:decode) => R.raw(:DecodeFn)
            }

      @spec build(R.slice(R.path(:Field))) :: R.nif_result(R.unit())
      defrust(build(_fields), do: :ok)

      defrustmacro descriptor(
                     fn: name(:ident),
                     env: env(:ident),
                     fields:
                       repeat do
                         field_id(:literal)
                         field_repeated(:literal)
                         field_decode(:ident)
                       end
                   ) do
        @spec name(R.path(:Env, R.lifetime(:a))) :: R.nif_result(R.unit())
        defrust name(_env) do
          build(
            ref(
              array([
                repeat fields do
                  struct_literal(Field,
                    id: field_id,
                    repeated: field_repeated,
                    decode: field_decode
                  )
                end
              ])
            )
          )
        end
      end
    end

    call =
      RustQ.Meta.AST.macro_call!(DefrustMacroItemCallCase, :descriptor,
        fn: :decode_user,
        env: :env,
        fields: [
          [field_id: 1, field_repeated: false, field_decode: :decode_name],
          [field_id: 2, field_repeated: true, field_decode: :decode_tags]
        ]
      )

    source =
      [
        RustQ.Meta.AST.macro_item!(DefrustMacroItemCallCase, :descriptor),
        call
      ]
      |> Enum.map_join("\n", &RustQ.Rust.to_fragment/1)

    assert source =~ "macro_rules! descriptor"
    assert source =~ "descriptor!"
    assert source =~ "fn decode_user;"
    assert source =~ "env env;"
    assert source =~ "1 => false decode_name;"
    assert source =~ "2 => true decode_tags;"
    assert RustQ.valid?(source, "defrustmacro_item_call.rs")
  end

  test "semantic defrustmacro item calls support full message field rows" do
    defmodule DefrustMacroFullMessageItemCallCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type field :: %{
              required(:id) => R.u32(),
              required(:index) => R.usize(),
              required(:repeated) => R.bool(),
              required(:decode) => R.raw(:DecodeFn)
            }

      @spec build(R.slice(R.path(:Field))) :: R.nif_result(R.unit())
      defrust(build(_fields), do: :ok)

      defrustmacro descriptor(
                     fn: name(:ident),
                     fields:
                       repeat do
                         field_id(:literal)
                         field_index(:literal)
                         field_repeated(:literal)
                         field_decode(:ident)
                       end
                   ) do
        @spec name() :: R.nif_result(R.unit())
        defrust name() do
          build(
            ref(
              array([
                repeat fields do
                  struct_literal(Field,
                    id: field_id,
                    index: field_index,
                    repeated: field_repeated,
                    decode: field_decode
                  )
                end
              ])
            )
          )
        end
      end
    end

    call =
      RustQ.Meta.AST.macro_call!(DefrustMacroFullMessageItemCallCase, :descriptor,
        fn: :decode_message,
        fields: [
          [field_id: 1, field_index: 1, field_repeated: false, field_decode: :decode_id],
          [field_id: 2, field_index: 2, field_repeated: true, field_decode: :decode_children]
        ]
      )

    source =
      [
        RustQ.Meta.AST.macro_item!(DefrustMacroFullMessageItemCallCase, :descriptor),
        call
      ]
      |> Enum.map_join("\n", &RustQ.Rust.to_fragment/1)

    assert source =~
             "$field_id:literal => $field_index:literal: $field_repeated:literal $field_decode:ident;"

    assert source =~ "1 => 1: false decode_id;"
    assert source =~ "2 => 2: true decode_children;"
    assert RustQ.valid?(source, "defrustmacro_full_message_item_call.rs")
  end

  test "semantic defrustmacro item calls support one-capture field repetitions" do
    defmodule DefrustMacroOneCaptureItemCallCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec build(R.slice(R.u32())) :: R.nif_result(R.unit())
      defrust(build(_fields), do: :ok)

      defrustmacro descriptor(
                     fn: name(:ident),
                     fields:
                       repeat do
                         field_expr(:expr)
                       end
                   ) do
        @spec name() :: R.nif_result(R.unit())
        defrust name() do
          build(
            ref(
              array([
                repeat fields do
                  field_expr
                end
              ])
            )
          )
        end
      end
    end

    call =
      RustQ.Meta.AST.macro_call!(DefrustMacroOneCaptureItemCallCase, :descriptor,
        fn: :decode_values,
        fields: [
          [field_expr: "1 + 2"],
          [field_expr: "3 + 4"]
        ]
      )

    source =
      [
        RustQ.Meta.AST.macro_item!(DefrustMacroOneCaptureItemCallCase, :descriptor),
        call
      ]
      |> Enum.map_join("\n", &RustQ.Rust.to_fragment/1)

    assert source =~ "fields [$("
    assert source =~ "1 + 2;"
    assert source =~ "3 + 4;"
    assert RustQ.valid?(source, "defrustmacro_one_capture_item_call.rs")
  end

  test "selects defrustmacro items by name" do
    defmodule DefrustMacroSelectorCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec required_field(R.term(), binary()) :: R.nif_result(R.term())
      defrust required_field(term, _name) do
        {:ok, term}
      end

      defrustmacro field(term, name, type: :ty) do
        decode_as!(required_field(term, name), type)
      end
    end

    [field] = RustQ.Meta.AST.macro_items!(DefrustMacroSelectorCase, [:field])
    source = RustQ.Rust.to_fragment(field)

    assert source =~ "macro_rules! field"
    assert source =~ "required_field($term, $name)?.decode::<$type>()?"

    assert_raise ArgumentError, ~r/no defrustmacro item named missing/, fn ->
      RustQ.Meta.AST.macro_item!(DefrustMacroSelectorCase, :missing)
    end
  end

  test "defrustmacro groups with defrustmod functions" do
    defmodule DefrustMacroModuleCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      defrustmod Helpers, as: :helpers do
        defrustmacro identity(value) do
          value
        end

        @spec decode(R.u32()) :: R.u32()
        defrust decode(value) do
          identity!(value)
        end
      end
    end

    source = DefrustMacroModuleCase.__rustq_source__()

    assert source =~ "mod helpers"
    assert source =~ "macro_rules! identity"
    assert source =~ "fn decode(value: u32) -> u32"
    assert source =~ "identity!(value)"
    assert RustQ.valid?(source, "defrustmacro_module.rs")
  end

  test "defrust lowers remote Rust macro calls" do
    defmodule RemoteRustMacroCallCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec log_value(R.u32()) :: R.nif_result(R.unit())
      defrust log_value(value) do
        Debug.trace!(value)
        :ok
      end
    end

    source = RemoteRustMacroCallCase.__rustq_source__()

    assert source =~ "Debug::trace!(value);"
    assert RustQ.valid?(source, "remote_rust_macro_call.rs")
  end

  test "defrustmacro reports unsupported fragment annotations" do
    quoted =
      quote do
        defmodule UnsupportedDefrustMacroFragmentCase do
          use RustQ.Meta

          defrustmacro ok(value: :pat) do
            value
          end
        end
      end

    assert_raise Diagnostic.Error, ~r/unsupported Rust macro fragment :pat/, fn ->
      Code.compile_quoted(quoted)
    end
  end

  test "defrustmacro reports duplicate macro names" do
    quoted =
      quote do
        defmodule DuplicateDefrustMacroCase do
          use RustQ.Meta

          defrustmacro same(value) do
            value
          end

          defrustmacro same(left, right) do
            left + right
          end
        end
      end

    assert_raise Diagnostic.Error, ~r/duplicate defrustmacro same/, fn ->
      Code.compile_quoted(quoted)
    end
  end

  test "defrustmacro reports duplicate argument names" do
    quoted =
      quote do
        defmodule DuplicateDefrustMacroArgumentCase do
          use RustQ.Meta

          defrustmacro bad(value, value) do
            value
          end
        end
      end

    assert_raise Diagnostic.Error, ~r/duplicate argument value in defrustmacro bad/, fn ->
      Code.compile_quoted(quoted)
    end
  end

  test "defrustmacro reports type macro variables used as expressions" do
    quoted =
      quote do
        defmodule TypeMacroVariableExpressionCase do
          use RustQ.Meta

          defrustmacro bad(type: :ty) do
            type
          end
        end
      end

    assert_raise Diagnostic.Error,
                 ~r/type is a Rust type fragment, but this is an expression position/,
                 fn ->
                   Code.compile_quoted(quoted)
                 end
  end

  test "defrustmacro reports arity mismatches at macro call sites" do
    quoted =
      quote do
        defmodule DefrustMacroArityMismatchCase do
          use RustQ.Meta
          alias RustQ.Type, as: R

          defrustmacro passthrough(value) do
            value
          end

          @spec decode(R.term()) :: R.term()
          defrust decode(term) do
            passthrough!()
          end
        end
      end

    assert_raise Diagnostic.Error, ~r/macro passthrough! expects 1 arguments, got 0/, fn ->
      Code.compile_quoted(quoted)
    end
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

  test "defrust uses rust source method metadata for discarded fallible statements" do
    defmodule RustSourceMethodPropagationCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/decoder_metadata.rs"]
      alias RustQ.Type, as: R

      @spec skip(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) :: R.nif_result(R.unit())
      defrust skip(decoder) do
        decoder.read_var_int64()
        :ok
      end
    end

    source = RustSourceMethodPropagationCase.__rustq_source__()

    assert source =~ "decoder.read_var_int64()?;"
    assert source =~ "Ok(())"
    assert RustQ.valid?(source, "rust_source_method_propagation.rs")
  end

  defmodule SynSourceDomain do
    defmacro __using__(_opts) do
      quote do
        use RustQ.Meta, rust_sources: ["test/fixtures/external_callables.rs"]
      end
    end
  end

  test "defrust lowers case when guards" do
    defmodule CaseWhenGuardCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode(term()) :: R.nif_result(R.u32())
      defrust decode(term) do
        case decode_as(term, {atom(), R.u32()}) do
          {:ok, {tag, value}} when tag == Atoms.count() and value > 0 -> {:ok, value}
          {:ok, {_tag, _value}} -> {:error, badarg()}
          {:error, _reason} -> {:error, badarg()}
        end
      end
    end

    source = CaseWhenGuardCase.__rustq_source__()

    assert source =~ "Ok((tag, value)) if tag == atoms::count() && value > 0 =>"
    assert source =~ "Ok(value)"
    assert RustQ.valid?(source, "case_when_guard_case.rs")
  end

  test "defrust lowers with expressions for result-oriented alternatives" do
    defmodule WithResultCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode_color(term()) :: R.nif_result(R.u32())
      defrust decode_color(term) do
        case term do
          1 -> {:ok, 10}
          _ -> {:error, badarg()}
        end
      end

      @spec decode_shader(term()) :: R.nif_result(R.u32())
      defrust decode_shader(term) do
        case term do
          2 -> {:ok, 20}
          _ -> {:error, badarg()}
        end
      end

      @spec decode(term()) :: R.nif_result(R.u32())
      defrust decode(term) do
        with {:error, _color_reason} <- decode_color(term),
             {:error, _shader_reason} <- decode_shader(term) do
          {:error, badarg()}
        else
          {:ok, value} -> {:ok, value + 1}
          {:error, _reason} -> {:error, badarg()}
        end
      end
    end

    source = WithResultCase.__rustq_source__()

    assert source =~ "match decode_color(term)"
    assert source =~ "Err(_color_reason) =>"
    assert source =~ "match __rustq_with_value"
    assert source =~ "Ok(value) =>"
    assert source =~ "Ok(value + 1)"
    refute source =~ "return "
    assert RustQ.valid?(source, "with_result_case.rs")
  end

  test "defrust lowers for reduce as an expression-valued fallible loop" do
    defmodule ForReduceResultCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec validate(R.vec(R.u32())) :: R.nif_result(R.unit())
      defrust validate(values) do
        for value <- values, reduce: :ok do
          :ok ->
            if value == 0 do
              {:error, badarg()}
            else
              :ok
            end
        end
      end
    end

    source = ForReduceResultCase.__rustq_source__()

    assert source =~ "let mut __rustq_reduce = Ok(());"
    assert source =~ "for value in values"
    assert source =~ "__rustq_reduce = match __rustq_reduce"
    assert source =~ "Ok(()) =>"
    assert source =~ "__rustq_reduce_value =>"
    assert source =~ "Err(rustler::Error::BadArg)"
    refute source =~ "return "
    assert RustQ.valid?(source, "for_reduce_result_case.rs")
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

  test "defrust infers propagation through parent-module Rust calls" do
    defmodule SynParentCallableCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/external_callables.rs"]

      alias RustQ.Type, as: R

      @spec decode_color(R.term()) :: R.nif_result(R.path(:Color))
      defrust decode_color(term) do
        color = decode_as!(term, R.u32())
        {:ok, Color.from_argb(255, 0, 0, color)}
      end

      @spec draw(R.term(), R.slice({R.atom(), R.term()})) :: R.nif_result(R.path(:Paint))
      defrust draw(term, opts) do
        Super.stroke_paint(decode_color(term), 1.0, opts)
      end
    end

    source = SynParentCallableCase.__rustq_source__()

    assert source =~ "super::stroke_paint(decode_color(term)?, 1.0, opts)"
    assert RustQ.valid?(source, "syn_parent_callable.rs")
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

  test "__rustq_callables__ exports local specs without duplicating external metadata" do
    defmodule ExternalMetadataExportCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/external_callables.rs"]

      alias RustQ.Type, as: R

      @spec decode_color(R.term()) :: R.nif_result(R.path(:Color))
      defrust decode_color(term) do
        color = decode_as!(term, R.u32())
        {:ok, Color.from_argb(255, 0, 0, color)}
      end
    end

    names = Enum.map(ExternalMetadataExportCase.__rustq_callables__(), & &1.name)

    assert "decode_color" in names
    refute "stroke_paint" in names
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

  test "unknown RustQ.Meta options raise structured diagnostics" do
    error =
      assert_raise Diagnostic.Error, fn ->
        defmodule UnknownMetaOptionCase do
          use RustQ.Meta, rust_source: "test/fixtures/external_callables.rs"
        end
      end

    assert %Diagnostic{phase: :defrust, kind: :invalid_meta_option} = error.diagnostic
    assert error.diagnostic.details.key == :rust_source
  end

  test "malformed RustQ.Meta callable metadata options raise structured diagnostics" do
    error =
      assert_raise Diagnostic.Error, fn ->
        defmodule MalformedMetaOptionCase do
          use RustQ.Meta, rust_packages: [123]
        end
      end

    assert %Diagnostic{phase: :defrust, kind: :invalid_meta_option} = error.diagnostic
    assert error.diagnostic.details.key == :rust_packages
  end

  test "Rust source callable metadata preserves cross-file public aliases" do
    unique = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "rustq_source_aliases_#{unique}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    paint_path = Path.join(dir, "paint.rs")
    core_path = Path.join(dir, "core.rs")
    generated_path = Path.join(dir, "generated.rs")

    File.write!(paint_path, """
    pub use sb::SkPaint_Cap as Cap;

    impl Paint {
      pub fn set_stroke_cap(&mut self, cap: Cap) -> &mut Self { self }
    }
    """)

    File.write!(core_path, "pub use paint::Cap as PaintCap;\n")
    File.write!(generated_path, "fn decode(atom: Atom) -> NifResult<PaintCap> { todo!() }\n")

    module = Module.concat(__MODULE__, :CrossFileRustSourceAliasesCase)

    Module.create(
      module,
      quote do
        use RustQ.Meta,
          rust_sources: unquote(Macro.escape([paint_path, core_path, generated_path]))

        alias RustQ.Type, as: R

        @spec run(R.mut_ref(Paint.t()), R.atom()) :: R.nif_result(R.unit())
        defrust run(paint, atom) do
          paint.set_stroke_cap(decode(atom))
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    assert module.__rustq_source__() =~ "paint.set_stroke_cap(decode(atom)?);"
  end

  test "infers propagation through source-backed From impl into Into argument" do
    unique = System.unique_integer([:positive])
    path = Path.join(System.tmp_dir!(), "rustq_from_into_#{unique}.rs")
    on_exit(fn -> File.rm(path) end)

    File.write!(path, """
    struct Color;
    struct Color4f;
    struct ImageFilter;

    impl From<Color> for Color4f {
      fn from(color: Color) -> Self { todo!() }
    }

    fn drop_shadow(color: impl Into<Color4f>) -> Option<ImageFilter> { todo!() }
    """)

    module = Module.concat(__MODULE__, :FromIntoArgumentCase)

    Module.create(
      module,
      quote do
        use RustQ.Meta, rust_sources: [unquote(path)]
        alias RustQ.Type, as: R

        @spec decode_color(term()) :: R.nif_result(R.path(:Color))
        defrust decode_color(term) do
          _value = decode_as!(term, R.u32())
          {:ok, Color.default()}
        end

        @spec run(term()) :: R.nif_result(R.unit())
        defrust run(term) do
          drop_shadow(decode_color(term))
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    assert module.__rustq_source__() =~ "drop_shadow(decode_color(term)?);"
  end

  test "Rust source callable cache refreshes when the source file changes" do
    unique = System.unique_integer([:positive])
    path = Path.join(System.tmp_dir!(), "rustq_source_cache_#{unique}.rs")
    on_exit(fn -> File.rm(path) end)

    File.write!(path, "fn consume_first(color: Color) -> NifResult<()> { todo!() }\n")

    first_module = Module.concat(__MODULE__, :FreshRustSourceFirst)

    Module.create(
      first_module,
      quote do
        use RustQ.Meta, rust_sources: [unquote(path)]
        alias RustQ.Type, as: R

        @spec decode(atom()) :: R.nif_result(R.path(:Color))
        defrust decode(atom) do
          color = decode_as!(atom, R.u32())
          {:ok, Color.from_argb(255, color, 0, 0)}
        end

        @spec run(atom()) :: R.nif_result(R.unit())
        defrust run(atom) do
          consume_first(decode(atom))
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    assert first_module.__rustq_source__() =~ "consume_first(decode(atom)?)?;"

    File.write!(path, "fn consume_second(color: Color) -> NifResult<()> { todo!() }\n")

    second_module = Module.concat(__MODULE__, :FreshRustSourceSecond)

    Module.create(
      second_module,
      quote do
        use RustQ.Meta, rust_sources: [unquote(path)]
        alias RustQ.Type, as: R

        @spec decode(atom()) :: R.nif_result(R.path(:Color))
        defrust decode(atom) do
          color = decode_as!(atom, R.u32())
          {:ok, Color.from_argb(255, color, 0, 0)}
        end

        @spec run(atom()) :: R.nif_result(R.unit())
        defrust run(atom) do
          consume_second(decode(atom))
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    assert second_module.__rustq_source__() =~ "consume_second(decode(atom)?)?;"
  end

  test "configured Rust sources raise structured diagnostics" do
    error =
      assert_raise Diagnostic.Error, fn ->
        defmodule InvalidRustSourceConfigCase do
          use RustQ.Meta, rust_sources: ["test/fixtures/missing_external_callables.rs"]
          alias RustQ.Type, as: R

          @spec run() :: R.nif_result(R.unit())
          defrust run do
            :ok
          end
        end
      end

    assert %Diagnostic{phase: :defrust, kind: :invalid_rust_source} = error.diagnostic
    assert error.diagnostic.details.path =~ "missing_external_callables.rs"
  end

  test "configured Rust packages raise structured diagnostics" do
    error =
      assert_raise Diagnostic.Error, fn ->
        defmodule InvalidRustPackageConfigCase do
          use RustQ.Meta, rust_packages: ["definitely-not-a-real-rustq-test-package"]
          alias RustQ.Type, as: R

          @spec run() :: R.nif_result(R.unit())
          defrust run do
            :ok
          end
        end
      end

    assert %Diagnostic{phase: :defrust, kind: :rust_package_load_failed} = error.diagnostic
    assert error.diagnostic.details.package == "definitely-not-a-real-rustq-test-package"
  end

  test "configured callable modules must expose callable metadata" do
    error =
      assert_raise Diagnostic.Error, fn ->
        defmodule InvalidCallableModuleConfigCase do
          use RustQ.Meta, callable_modules: [String]
          alias RustQ.Type, as: R

          @spec run() :: R.nif_result(R.unit())
          defrust run do
            :ok
          end
        end
      end

    assert %Diagnostic{phase: :defrust, kind: :invalid_callable_module} = error.diagnostic
    assert error.diagnostic.details.module == String
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

  test "defrust auto-borrows fields reached through slice get unwrap" do
    defmodule AutoBorrowSliceFieldCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type kind :: R.enum(one: [], repeated: [])
      @type field :: %{required(:kind) => kind()}

      @spec use_kind(R.ref(kind())) :: R.nif_result(R.unit())
      defrust(use_kind(_kind), do: :ok)

      @spec run(R.slice(field()), R.usize()) :: R.nif_result(R.unit())
      defrust run(fields, index) do
        field = fields.get(index).unwrap()
        use_kind(field.kind)
        :ok
      end
    end

    source = AutoBorrowSliceFieldCase.__rustq_source__()

    assert source =~ "use_kind(&field.kind)?;"
    assert RustQ.valid?(source, "auto_borrow_slice_field.rs")
  end

  test "defrust auto-borrows struct field access from expected ref types" do
    defmodule AutoBorrowStructFieldCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type kind :: R.enum(one: [], repeated: [])
      @type field :: %{required(:kind) => kind()}

      @spec use_kind(R.ref(kind())) :: R.nif_result(R.unit())
      defrust(use_kind(_kind), do: :ok)

      @spec run(field()) :: R.nif_result(R.unit())
      defrust run(field) do
        use_kind(field.kind)
        :ok
      end
    end

    source = AutoBorrowStructFieldCase.__rustq_source__()

    assert source =~ "use_kind(&field.kind)?;"
    assert RustQ.valid?(source, "auto_borrow_struct_field.rs")
  end

  test "defrust checks closure bodies against expected callback return type" do
    defmodule AutoBorrowClosureReturnCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec with_callback(R.raw(:"fn() -> &Color")) :: R.nif_result(R.unit())
      defrust(with_callback(_callback), do: :ok)

      @spec run(R.raw(:Color)) :: R.nif_result(R.unit())
      defrust run(color) do
        with_callback(fn -> color end)
        :ok
      end
    end

    source = AutoBorrowClosureReturnCase.__rustq_source__()

    assert source =~ "with_callback(|| &color)?;"
  end

  test "defrust auto-borrows array literals for expected slices" do
    defmodule AutoBorrowArraySliceCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec use_values(R.slice(R.u32())) :: R.nif_result(R.unit())
      defrust(use_values(_values), do: :ok)

      @spec run() :: R.nif_result(R.unit())
      defrust run() do
        use_values(array([1, 2, 3]))
        :ok
      end
    end

    source = AutoBorrowArraySliceCase.__rustq_source__()

    assert source =~ "use_values(&[1, 2, 3])?;"
    assert RustQ.valid?(source, "auto_borrow_array_slice.rs")
  end

  test "defrust propagates let RHS through downstream comparisons" do
    defmodule PropagateLetComparisonCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @type field :: %{required(:id) => R.u32()}

      @spec read_id() :: R.nif_result(R.u32())
      defrust(read_id(), do: {:ok, 0})

      @spec run(R.slice(field())) :: R.nif_result(R.unit())
      defrust run(fields) do
        field_id = read_id()

        if field_id == 0 do
          :ok
        else
          case fields.binary_search_by_key(field_id, fn field -> field.id end) do
            {:ok, _index} -> :ok
            {:error, _index} -> {:error, badarg()}
          end
        end
      end
    end

    source = PropagateLetComparisonCase.__rustq_source__()

    assert source =~ "let field_id = read_id()?;"
    assert source =~ "fields.binary_search_by_key(&field_id, |field| field.id)"
    assert RustQ.valid?(source, "propagate_let_comparison.rs")
  end

  test "defrust propagates call arguments through mutable vec push" do
    defmodule PropagateMutRefVecPushCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode_value() :: R.nif_result(term())
      defrust(decode_value(), do: {:ok, make_term()})

      @spec make_term() :: term()
      defrust(make_term(), do: 0)

      @spec run(R.mut_ref(R.vec(term()))) :: R.nif_result(R.unit())
      defrust run(values) do
        values.push(decode_value())
        :ok
      end
    end

    source = PropagateMutRefVecPushCase.__rustq_source__()

    assert source =~ "values.push(decode_value()?);"
    assert RustQ.valid?(source, "propagate_mut_ref_vec_push.rs")
  end

  test "defrust auto-borrows configured generated static items" do
    defmodule AutoBorrowConfiguredStaticCase do
      use RustQ.Meta, static_types: [GUID_ATOM: RustQ.Type.raw(:"OnceLock<Atom>")]
      alias RustQ.Type, as: R

      @spec cached_atom(R.ref(R.raw(:"OnceLock<Atom>"))) :: R.nif_result(R.unit())
      defrust(cached_atom(_cell), do: :ok)

      @spec run() :: R.nif_result(R.unit())
      defrust run() do
        cached_atom(GUID_ATOM)
        :ok
      end
    end

    source = AutoBorrowConfiguredStaticCase.__rustq_source__()

    assert source =~ "cached_atom(&GUID_ATOM)?;"
  end

  test "defrust auto-borrows external static items from rust source metadata" do
    defmodule AutoBorrowExternalStaticCase do
      use RustQ.Meta, rust_sources: ["test/fixtures/external_statics.rs"]
      alias RustQ.Type, as: R

      @spec cached_atom(R.ref(R.raw(:"OnceLock<Atom>"))) :: R.nif_result(R.unit())
      defrust(cached_atom(_cell), do: :ok)

      @spec run() :: R.nif_result(R.unit())
      defrust run() do
        cached_atom(GUID_ATOM)
        :ok
      end
    end

    source = AutoBorrowExternalStaticCase.__rustq_source__()

    assert source =~ "cached_atom(&GUID_ATOM)?;"
  end

  test "defrust checks with bodies against expected call argument type" do
    defmodule AutoBorrowWithBodyCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec maybe_color(R.bool(), R.raw(:Color)) :: R.nif_result(R.raw(:Color))
      defrust maybe_color(flag, color) do
        if flag do
          {:ok, color}
        else
          {:error, badarg()}
        end
      end

      @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
      defrust(use_color(_color), do: :ok)

      @spec run(R.raw(:Color), R.bool()) :: R.nif_result(R.unit())
      defrust run(color, flag) do
        use_color(
          case maybe_color(flag, color) do
            {:ok, value} -> value
            _reason -> color
          end
        )

        :ok
      end
    end

    source = AutoBorrowWithBodyCase.__rustq_source__()

    assert source =~ "Ok(value) => &value"
    assert source =~ "_reason => &color"
    assert RustQ.valid?(source, "auto_borrow_with_body.rs")
  end

  test "defrust checks for reduce arms against expected accumulator type" do
    defmodule AutoBorrowForReduceCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
      defrust(use_color(_color), do: :ok)

      @spec run(R.raw(:Color), R.vec(R.bool())) :: R.nif_result(R.unit())
      defrust run(color, flags) do
        use_color(
          for flag <- flags, reduce: color do
            acc ->
              if flag do
                acc
              else
                acc
              end
          end
        )

        :ok
      end
    end

    source = AutoBorrowForReduceCase.__rustq_source__()

    assert source =~ "let mut __rustq_reduce = &color;"
    assert source =~ "if flag { acc } else { acc }"
    assert RustQ.valid?(source, "auto_borrow_for_reduce.rs")
  end

  test "defrust checks if branches against expected call argument type" do
    defmodule AutoBorrowIfBranchCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
      defrust(use_color(_color), do: :ok)

      @spec run(R.raw(:Color), R.bool()) :: R.nif_result(R.unit())
      defrust run(color, flag) do
        use_color(
          if flag do
            color
          else
            color
          end
        )

        :ok
      end
    end

    source = AutoBorrowIfBranchCase.__rustq_source__()

    assert source =~ "if flag { &color } else { &color }"

    assert RustQ.valid?(source, "auto_borrow_if_branch.rs")
  end

  test "defrust checks case arms against expected call argument type" do
    defmodule AutoBorrowCaseArmCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
      defrust(use_color(_color), do: :ok)

      @spec run(R.raw(:Color), R.u32()) :: R.nif_result(R.unit())
      defrust run(color, flag) do
        use_color(
          case flag do
            0 -> color
            1 -> color
          end
        )

        :ok
      end
    end

    source = AutoBorrowCaseArmCase.__rustq_source__()

    assert source =~ "0 => &color"
    assert source =~ "1 => &color"
    assert RustQ.valid?(source, "auto_borrow_case_arm.rs")
  end

  test "defrust auto-borrows call arguments from expected ref types" do
    defmodule AutoBorrowCallArgumentCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec use_color(R.ref(R.raw(:Color))) :: R.nif_result(R.unit())
      defrust(use_color(_color), do: :ok)

      @spec mutate_color(R.mut_ref(R.raw(:Color))) :: R.nif_result(R.unit())
      defrust(mutate_color(_color), do: :ok)

      @spec run(R.raw(:Color)) :: R.nif_result(R.unit())
      defrust run(color) do
        use_color(color)
        mutate_color(color)
        :ok
      end
    end

    source = AutoBorrowCallArgumentCase.__rustq_source__()

    assert source =~ "use_color(&color)?;"
    assert source =~ "mutate_color(&mut color)?;"
    assert RustQ.valid?(source, "auto_borrow_call_argument.rs")
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
    assert source =~ "if let Some(mut paint) = maybe_paint"
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
    item = MetaAST.function!(RustQ.Meta.GeneratedCase, :draw_save)

    assert RustQ.Rust.to_fragment(item) =~ "fn draw_save"

    assert_raise ArgumentError, fn ->
      MetaAST.function!(RustQ.Meta.GeneratedCase, :missing)
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

  test "defrust lowers structural Rust enum variants" do
    defmodule EnumVariantCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec one(R.raw(:SkipFn)) :: R.raw(:KiwiSkipKind)
      defrust one(skip) do
        enum_variant(KiwiSkipKind, :one, skip)
      end

      @spec bytes() :: R.raw(:KiwiSkipKind)
      defrust bytes() do
        enum_variant(KiwiSkipKind, :bytes)
      end
    end

    source = EnumVariantCase.__rustq_source__()

    assert source =~ "KiwiSkipKind::One(skip)"
    assert source =~ "KiwiSkipKind::Bytes"
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

  test "renders assign bang arithmetic as compound assignment" do
    defmodule AssignBangCompoundCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec count() :: R.usize()
      defrust count() do
        count = 2
        assign!(count, count + 1)
        count
      end
    end

    source = AssignBangCompoundCase.__rustq_source__()
    assert source =~ "let mut count = 2;"
    assert source =~ "count += 1;"
  end

  test "renders assign bang Bitwise operations as compound assignment" do
    defmodule AssignBangBitwiseCompoundCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec masked(R.u32()) :: R.u32()
      defrust masked(mask) do
        value = 255
        assign!(value, Bitwise.band(value, mask))
        value
      end
    end

    source = AssignBangBitwiseCompoundCase.__rustq_source__()
    assert source =~ "value &= mask;"
  end

  test "lowers statement option cases with unit none branch to if let" do
    defmodule OptionCaseIfLetStatementCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec attr(R.option(R.path(:String)), R.usize()) :: R.raw(:"Option<(&'static str, String)>")
      defrust attr(name, index) do
        cursor = 0

        case name.as_ref() do
          {:some, value} ->
            if index == cursor do
              return!(some({"name", value.clone()}))
            end

            assign!(cursor, cursor + 1)

          :none ->
            :ok
        end

        nil
      end
    end

    source = OptionCaseIfLetStatementCase.__rustq_source__()
    assert source =~ "if let Some(value) = name.as_ref()"
    assert source =~ "cursor += 1;"
    refute source =~ "match name.as_ref()"
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

    assert source =~ "1 =>"
    assert source =~ "2 =>"
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

    assert Nif.render_ast(draw_save) =~
             "fn draw_save(canvas: &Canvas) -> NifResult<()>"

    assert Nif.render_ast(draw_save) =~ "canvas.save();"
  end

  test "generated items remain structural RustQ AST" do
    assert Enum.all?(Generated.__rustq_items__(), fn item ->
             item.__struct__.__rustq_ast_category__() == :item
           end)
  end
end
