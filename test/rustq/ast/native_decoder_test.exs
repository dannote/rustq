defmodule RustQ.Rust.AST.NativeDecoderTest do
  use ExUnit.Case, async: true

  alias RustQ.Native
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  require A

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
            A.return(A.ok())
          end
      })

    assert source =~ "opts.fill;"
    assert source =~ "Rect::from_xywh(x, y, width, height);"
    assert source =~ "canvas.draw_rect(&rect, &mut paint);"
  end

  test "native decoder renders typed let statements" do
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

  test "generated expression decoders render literal, token macro, and binary expressions" do
    literal_source =
      Native.render_ast(%AST.Function{
        name: :literal_expr,
        args: [],
        returns: "&'static str",
        body: A.block(do: A.return(A.lit("hello")))
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

    assert literal_source =~ ~s|"hello"|
    assert token_macro_source =~ "quote!(None)"
    assert binary_source =~ "left == right && ok"
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
                A.arm A.ok_pat(:inner) do
                  A.return(A.ok(:inner))
                end

                A.arm A.err_pat(:reason) do
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
                [A.return(A.err(A.path([:rustler, :Error, :BadArg])))]
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
        body: A.block(do: A.return(A.err(A.path([:rustler, :Error, :BadArg]))))
      })

    assert try_source =~ "fallible()?"
    assert tuple_source =~ "(left, right)"
    assert some_source =~ "Some(value)"
    assert err_source =~ "Err(rustler::Error::BadArg)"
  end
end
