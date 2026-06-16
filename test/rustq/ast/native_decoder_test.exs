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
