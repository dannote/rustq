Code.require_file("../../../support/rustq_ast_samples.ex", __DIR__)

defmodule RustQ.Rust.AST.NativeDecoderTest do
  use ExUnit.Case, async: true

  alias RustQ.Diagnostic
  alias RustQ.Native
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.Function
  alias RustQ.Rust.AST.PatternBuilder, as: P
  alias RustQ.Rust.AST.Render
  alias RustQ.Rust.AST.Schema
  alias RustQ.Rust.AST.TypePath

  require A

  test "native AST rendering failures raise structured diagnostics" do
    invalid = %Function{name: :bad, args: [], returns: %TypePath{parts: []}, body: []}

    error = assert_raise Diagnostic.Error, fn -> Render.render_function(invalid) end
    diagnostic = error.diagnostic

    assert diagnostic.phase == :render
    assert diagnostic.kind == :native_render_failed
    assert diagnostic.details.ast_module == Function
    assert %ArgumentError{} = diagnostic.details.cause
    assert diagnostic.message =~ "native AST rendering failed"
    assert diagnostic.snippet =~ "%RustQ.Rust.AST.Function"
  end

  test "behavioral examples cover every current AST schema node" do
    samples = RustQ.ASTSamples.all()

    assert MapSet.new(Map.keys(samples)) ==
             Schema.nodes() |> Enum.map(& &1.name) |> MapSet.new()

    for {name, ast} <- samples do
      source = Native.render_ast(ast)
      assert is_binary(source), "sample for #{name} should render"

      assert RustQ.ASTSamples.validate_rendered?(name, ast, source),
             "sample for #{name} should render expected behavior, got:\n#{source}"
    end
  end

  test "dogfooded item and type decoders render use, module, macro, constants, structs, and enums" do
    use_source = Native.render_ast(%AST.Use{tree: "std::fmt"})

    module_source =
      Native.render_ast(%AST.Module{
        name: :generated,
        vis: :crate,
        items: [%AST.Const{name: :ANSWER, type: A.type_path(:u32), expr: A.lit(42)}]
      })

    macro_source = Native.render_ast(%AST.MacroItem{source: "type Alias = u32;"})

    const_source =
      Native.render_ast(%AST.Const{
        name: :LIMIT,
        type: %AST.TypeOption{inner: %AST.TypeRef{inner: A.type_path(:str), lifetime: :a}},
        expr: A.none(),
        vis: :crate
      })

    struct_source =
      Native.render_ast(%AST.Struct{
        name: :Holder,
        lifetime: :a,
        vis: :pub,
        fields: [
          %AST.StructField{
            name: :value,
            type: %AST.TypeRef{inner: A.type_path(:str), lifetime: :a},
            vis: :pub
          }
        ]
      })

    enum_source =
      Native.render_ast(%AST.Enum{
        name: :Maybe,
        vis: :pub,
        variants: [
          %AST.EnumVariant{name: :None},
          %AST.EnumVariant{name: :Some, tuple: [%AST.TypeVec{inner: A.type_path(:u8)}]}
        ]
      })

    assert use_source =~ "use std::fmt;"
    assert module_source =~ "pub(crate) mod generated"
    assert module_source =~ "const ANSWER: u32 = 42i64;"
    assert macro_source =~ "type Alias = u32;"
    assert const_source =~ "pub(crate) const LIMIT: Option<&'a str> = None;"
    assert struct_source =~ "pub struct Holder<'a>"
    assert struct_source =~ "pub value: &'a str"
    assert enum_source =~ "pub enum Maybe"
    assert enum_source =~ "Some(Vec<u8>)"
  end

  test "generated statement decoders render expression and return statements" do
    source =
      Native.render_ast(%AST.Function{
        name: :statements,
        args: [],
        returns: "i32",
        body:
          A.block do
            A.stmt(A.call(:side_effect))
            A.return(A.var(:value))
          end
      })

    assert source =~ "side_effect();"
    assert source =~ "value"
  end

  test "generated expression decoders render field, calls, methods, and refs" do
    source =
      Native.render_ast(%AST.Function{
        name: :exprs,
        args: [],
        returns: "NifResult<()> ",
        body:
          A.block do
            A.stmt(%AST.Field{receiver: A.var(:opts), field: :fill})
            A.stmt(A.path_call([:Rect, :from_xywh], [:x, :y, :width, :height]))
            A.stmt(A.method(:canvas, :draw_rect, [A.ref(:rect), A.mut_ref(:paint)]))

            A.stmt(
              A.method(%AST.Cast{expr: A.var(:value), type: A.type_path(:f32)}, :to_ne_bytes)
            )

            A.return(A.ok())
          end
      })

    assert source =~ "opts.fill;"
    assert source =~ "Rect::from_xywh(x, y, width, height);"
    assert source =~ "canvas.draw_rect(&rect, &mut paint);"
    assert source =~ "(value as f32).to_ne_bytes();"
  end

  test "native decoder renders mutable and typed let statements" do
    mutable_source =
      Native.render_ast(%AST.Function{
        name: :mutable_let,
        args: [],
        returns: "String",
        body:
          A.block do
            A.let_mut(:tokens, A.call(:read_tokens))
            A.return(:tokens)
          end
      })

    assert mutable_source =~ "let mut tokens = read_tokens();"

    source =
      Native.render_ast(%AST.Function{
        name: :typed_let,
        args: [],
        returns: "String",
        body:
          A.block do
            A.let(:tokens, A.call(:read_tokens), type: "String")
            A.return(:tokens)
          end
      })

    assert source =~ "let tokens: String = read_tokens();"
  end

  test "generated expression decoders render local calls, struct literals, and ok expressions" do
    source =
      Native.render_ast(%AST.Function{
        name: :more_exprs,
        args: [],
        returns: "NifResult<Rect>",
        body:
          A.block do
            A.stmt(A.call(:todo!, []))

            A.return(
              A.ok(
                A.struct([:Rect],
                  x: A.var(:x),
                  y: A.var(:y)
                )
              )
            )
          end
      })

    assert source =~ "todo!();"
    assert source =~ "Ok(Rect { x: x, y: y })"
  end

  test "generated expression decoders render literal, token macro, and binary expressions" do
    literal_source =
      Native.render_ast(%AST.Function{
        name: :literal_expr,
        args: [],
        returns: "&'static str",
        body: A.block(do: A.return(A.lit("hello")))
      })

    float_source =
      Native.render_ast(%AST.Function{
        name: :float_expr,
        args: [],
        returns: "f32",
        body: A.block(do: A.return(A.lit(1.0)))
      })

    token_macro_source =
      Native.render_ast(%AST.Function{
        name: :token_macro_expr,
        args: [],
        returns: "TokenStream",
        body: A.block(do: A.return(A.token_macro(:quote, "None")))
      })

    binary_source =
      Native.render_ast(%AST.Function{
        name: :binary_expr,
        args: [],
        returns: "bool",
        body: A.block(do: A.return(A.and_(A.eq(:left, :right), :ok)))
      })

    deref_source =
      Native.render_ast(%AST.Function{
        name: :deref_expr,
        args: [value: "&i64"],
        returns: "i64",
        body: A.block(do: A.return(A.deref(:value)))
      })

    assert literal_source =~ ~s|"hello"|
    assert float_source =~ "1.0"
    refute float_source =~ "1f64"
    assert token_macro_source =~ "quote!(None)"
    assert binary_source =~ "left == right && ok"
    assert deref_source =~ "*value"
  end

  test "generated arm decoder renders atom guard patterns" do
    source =
      Native.render_ast(%AST.Function{
        name: :atom_guard,
        args: [value: "Atom"],
        returns: "i32",
        body:
          A.block do
            A.return do
              A.match A.var(:value) do
                A.arm %AST.PatAtomGuard{name: :ok} do
                  A.return(1)
                end

                A.arm A.wildcard() do
                  A.return(0)
                end
              end
            end
          end
      })

    assert source =~ "value if value == atoms::ok() =>"
  end

  test "generated pattern decoders render tuple, path tuple, and struct patterns" do
    source =
      Native.render_ast(%AST.Function{
        name: :pattern_exprs,
        args: [],
        returns: "i32",
        body:
          A.block do
            A.return do
              A.match A.var(:event) do
                A.arm %AST.PatTuple{patterns: [A.pat(:left), A.pat(:right)]} do
                  A.return(:left)
                end

                A.arm P.path_tuple([:Event, :Click], [P.var(:click)]) do
                  A.return(:click)
                end

                A.arm P.struct([:Click], name: P.var(:name)) do
                  A.return(:name)
                end
              end
            end
          end
      })

    assert source =~ "(left, right) =>"
    assert source =~ "Event::Click(click) =>"
    assert source =~ "Click { name: name } =>"
  end

  test "generated expression decoders render match, if, and raise atom expressions" do
    match_source =
      Native.render_ast(%AST.Function{
        name: :match_expr,
        args: [],
        returns: "NifResult<()> ",
        body:
          A.block do
            A.return do
              A.match A.var(:value) do
                A.arm P.ok(:inner) do
                  A.return(A.ok(:inner))
                end

                A.arm P.err(:reason) do
                  A.return(A.err(:reason))
                end
              end
            end
          end
      })

    if_source =
      Native.render_ast(%AST.Function{
        name: :if_expr,
        args: [],
        returns: "NifResult<()> ",
        body:
          A.block do
            A.return(
              A.if_expr(
                :condition,
                [A.return(A.ok())],
                [A.return_badarg()]
              )
            )
          end
      })

    raise_source =
      Native.render_ast(%AST.Function{
        name: :raise_expr,
        args: [],
        returns: "NifResult<()> ",
        body: A.block(do: A.return(%AST.NifRaiseAtom{name: :invalid}))
      })

    assert match_source =~ "match value"
    assert match_source =~ "Ok(inner)"
    assert if_source =~ "if condition"
    assert if_source =~ "Err(rustler::Error::BadArg)"
    assert raise_source =~ ~s|rustler::Error::RaiseAtom("invalid")|
  end

  test "generated expression decoders render try, tuple, some, and err expressions" do
    try_source =
      Native.render_ast(%AST.Function{
        name: :try_expr,
        args: [],
        returns: "NifResult<()> ",
        body: A.block(do: A.return(A.try(A.call(:fallible))))
      })

    tuple_source =
      Native.render_ast(%AST.Function{
        name: :tuple_expr,
        args: [],
        returns: "(i32, i32)",
        body: A.block(do: A.return(%AST.Tuple{values: [A.var(:left), A.var(:right)]}))
      })

    some_source =
      Native.render_ast(%AST.Function{
        name: :some_expr,
        args: [],
        returns: "Option<i32>",
        body: A.block(do: A.return(A.some(:value)))
      })

    err_source =
      Native.render_ast(%AST.Function{
        name: :err_expr,
        args: [],
        returns: "NifResult<()> ",
        body: A.block(do: A.return(A.err(A.badarg())))
      })

    assert try_source =~ "fallible()?"
    assert tuple_source =~ "(left, right)"
    assert some_source =~ "Some(value)"
    assert err_source =~ "Err(rustler::Error::BadArg)"
  end
end
