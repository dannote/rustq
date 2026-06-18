Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.AttrCase do
  use RustQ.Meta

  alias RustQ.Type, as: R

  @allow :dead_code
  @nif schedule: "DirtyCpu"
  @spec render(term()) :: R.nif_result(term())
  defrust render(term) do
    render_impl(term)
  end
end

defmodule RustQ.Meta.LowerTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.GeneratedCase, as: Generated
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  test "defrust consumes idiomatic Rust-facing attributes" do
    assert %RustQ.Rust.AST.Function{attrs: attrs} =
             RustQ.Meta.AttrCase.__rustq_asts__()
             |> Enum.find(&(&1.name == :render))

    assert [
             %RustQ.Rust.AST.Attribute{path: [:rustler, :nif], args: [schedule: "DirtyCpu"]},
             %RustQ.Rust.AST.Attribute{path: [:allow], args: [:dead_code]}
           ] = attrs

    source = RustQ.Meta.AttrCase.__rustq_source__()
    assert source =~ ~s|#[rustler::nif(schedule = "DirtyCpu")]|
    assert source =~ "#[allow(dead_code)]"
  end

  test "generated ASTs are retained before fragment validation" do
    [draw_save, decode_mode, draw_rect, maybe_save | _] = Generated.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{
             name: :draw_save,
             args: [%RustQ.Rust.AST.FunctionArg{name: :canvas, type: %RustQ.Rust.AST.TypeRef{}}]
           } = draw_save

    assert %RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}} = hd(decode_mode.body)

    assert %RustQ.Rust.AST.Function{
             args: [
               _canvas_arg,
               %RustQ.Rust.AST.FunctionArg{name: :opts, type: %RustQ.Rust.AST.TypePath{}},
               _raw_opts_arg
             ]
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

  test "closures and deref lower in method chains" do
    function =
      RustQ.Meta.quoted(:maybe_decode_color,
        args: [args: A.type_path(:Args)],
        returns: A.nif_result_type(A.unit_type()),
        do:
          quote do
            case args.first().and_then(fn term -> decode_color(deref(term)).ok() end) do
              {:some, color} -> canvas.clear(color)
              :none -> :ok
            end

            :ok
          end
      )

    source = RustQ.Rust.AST.Render.render_function(function)

    assert source =~ "args.first().and_then(|term| decode_color(*term).ok())"
    assert source =~ "Some(color) =>"
    assert source =~ "canvas.clear(color);"
  end

  test "option cases use Elixir tuple and atom patterns" do
    function =
      RustQ.Meta.quoted(:save_if_present,
        args: [
          canvas: A.ref_type(:Canvas),
          maybe_alpha: quote(do: RustQ.Type.option(RustQ.Type.f32()))
        ],
        returns: A.nif_result_type(A.unit_type()),
        do:
          quote do
            case maybe_alpha do
              {:some, alpha} -> canvas.save_layer_alpha(alpha)
              :none -> :ok
            end

            :ok
          end
      )

    assert %AST.Function{
             body: [
               %AST.ExprStmt{
                 expr: %AST.Match{
                   arms: [
                     %AST.Arm{pattern: %AST.PatSome{pattern: %AST.PatVar{name: :alpha}}},
                     %AST.Arm{pattern: %AST.PatNone{}}
                   ]
                 }
               },
               %AST.Return{expr: %AST.Ok{}}
             ]
           } = function

    source = RustQ.Rust.AST.Render.render_function(function)
    assert source =~ "Some(alpha) =>"
    assert source =~ "None =>"
  end

  test "dogfooded native helpers lower binary operators and Rust string types" do
    helpers = RustQ.NativeCodegen.Helpers.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{
             name: :required_field,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.MethodCall{method: :map_get}}]
           } = Enum.find(helpers, &(&1.name == :required_field))

    assert %RustQ.Rust.AST.Function{
             name: :optional_map_get,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}}]
           } = Enum.find(helpers, &(&1.name == :optional_map_get))

    assert %RustQ.Rust.AST.Function{
             name: :atom_key,
             args: [
               %RustQ.Rust.AST.FunctionArg{
                 name: :term,
                 type: %RustQ.Rust.AST.TypePath{parts: [:Term], lifetimes: [:a]}
               },
               %RustQ.Rust.AST.FunctionArg{
                 name: :key,
                 type: %RustQ.Rust.AST.TypeRef{inner: %RustQ.Rust.AST.TypePath{parts: [:str]}}
               }
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

  test "ordinary syntax lowers to RustQ AST while explicit expr helpers target syn" do
    draw_rect = Enum.find(Generated.__rustq_asts__(), &(&1.name == :draw_rect))

    decode_expr_ref =
      Enum.find(RustQ.NativeCodegen.Decoders.asts(), &(&1.name == :decode_expr_ref))

    assert Enum.any?(
             draw_rect.body,
             &match?(%RustQ.Rust.AST.ExprStmt{expr: %RustQ.Rust.AST.MethodCall{}}, &1)
           )

    assert inspect(draw_rect) =~ "RustQ.Rust.AST.Ref"

    assert %RustQ.Rust.AST.Function{
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{then: then_body, else: else_body}}
             ]
           } = decode_expr_ref

    assert [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.PathCall{path: then_path}}] = then_body
    assert [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.PathCall{path: else_path}}] = else_body
    assert then_path.parts == [:super, "parse_syn::<Expr>"]
    assert else_path.parts == [:super, "parse_syn::<Expr>"]
  end

  test "nested branches use expected return type wrapping" do
    asts = Generated.__rustq_asts__()

    assert %RustQ.Rust.AST.Function{
             name: :nested_option,
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.Match{arms: [nil_arm, value_arm]}
               }
             ]
           } = Enum.find(asts, &(&1.name == :nested_option))

    assert %RustQ.Rust.AST.Arm{body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.None{}}]} =
             nil_arm

    assert %RustQ.Rust.AST.Arm{
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.If{then: then_body, else: else_body}
               }
             ]
           } = value_arm

    assert [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.None{}}] = then_body

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Some{expr: %RustQ.Rust.AST.Var{name: :value}}
             }
           ] =
             else_body

    assert %RustQ.Rust.AST.Function{
             name: :nested_result,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{then: result_then}}]
           } = Enum.find(asts, &(&1.name == :nested_result))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Match{
                 arms: [
                   %RustQ.Rust.AST.Arm{
                     body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Ok{}}]
                   },
                   %RustQ.Rust.AST.Arm{
                     body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Err{}}]
                   }
                 ]
               }
             }
           ] = result_then

    assert %RustQ.Rust.AST.Function{
             name: :nested_nif_result,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{else: nif_else}}]
           } = Enum.find(asts, &(&1.name == :nested_nif_result))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Err{expr: %RustQ.Rust.AST.NifRaiseAtom{name: :not_ready}}
             }
           ] = nif_else
  end

  test "dogfooded decoder wrappers lower Super calls and Rust constructors" do
    decoders = RustQ.NativeCodegen.Decoders.asts()

    assert %RustQ.Rust.AST.Function{
             name: :decode_expr_try,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, "parse_syn::<Expr>"]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_try))

    assert %RustQ.Rust.AST.Function{
             name: :decode_pat_some,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, "parse_syn::<Pat>"]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_pat_some))

    assert %RustQ.Rust.AST.Function{
             name: :decode_stmt_return,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.Ok{
                   expr: %RustQ.Rust.AST.PathCall{
                     path: %RustQ.Rust.AST.Path{parts: [:Stmt, :Expr]}
                   }
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_stmt_return))

    assert %RustQ.Rust.AST.Function{
             name: :decode_expr_ok,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.Match{
                   arms: [
                     %RustQ.Rust.AST.Arm{pattern: %RustQ.Rust.AST.PatNone{}},
                     %RustQ.Rust.AST.Arm{pattern: %RustQ.Rust.AST.PatSome{}}
                   ]
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_ok))

    assert %RustQ.Rust.AST.Function{
             name: :decode_expr_none,
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, "parse_syn::<Expr>"]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_none))
  end
end
