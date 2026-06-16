Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.LowerTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.GeneratedCase, as: Generated

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

  test "dogfooded native helpers lower binary operators and Rust string types" do
    helpers = RustQ.NativeCodegen.Helpers.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{
             name: :optional_map_get,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}}]
           } = Enum.find(helpers, &(&1.name == :optional_map_get))

    assert %RustQ.Rust.AST.Function{
             name: :atom_key,
             args: [
               term: %RustQ.Rust.AST.TypePath{parts: [:Term], lifetimes: [:a]},
               key: %RustQ.Rust.AST.TypeRef{inner: %RustQ.Rust.AST.TypePath{parts: [:str]}}
             ],
             returns: %RustQ.Rust.AST.TypeNifResult{
               inner: %RustQ.Rust.AST.TypePath{parts: [:String]}
             }
           } = Enum.find(helpers, &(&1.name == :atom_key))

    assert %RustQ.Rust.AST.Function{name: :optional_atom_key, body: optional_body} =
             Enum.find(helpers, &(&1.name == :optional_atom_key))

    assert Enum.any?(
             optional_body,
             &match?(%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{}}, &1)
           )

    assert %RustQ.Rust.AST.Function{name: :is_nil, body: body} =
             Enum.find(helpers, &(&1.name == :is_nil))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Ok{expr: %RustQ.Rust.AST.BinaryOp{op: :and}}
             }
           ] =
             body

    assert %RustQ.Rust.AST.Function{
             name: :expect_struct,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{else: else_body}}]
           } =
             Enum.find(helpers, &(&1.name == :expect_struct))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Err{
                 expr: %RustQ.Rust.AST.Path{parts: [:rustler, :Error, :BadArg]}
               }
             }
           ] = else_body
  end

  test "dogfooded decoder wrappers lower Super calls to parent Rust module paths" do
    decoders = RustQ.NativeCodegen.Decoders.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{
             name: :decode_expr_none,
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, :parse_expr_tokens]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_none))
  end
end
