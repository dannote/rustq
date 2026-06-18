defmodule RustQ.NativeCodegen.HelperModulesTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  test "native defrust modules expose crate-visible ASTs" do
    assert %AST.Function{name: :required_field, vis: :crate} =
             Enum.find(RustQ.NativeCodegen.Helpers.asts(), &(&1.name == :required_field))

    assert %AST.Function{name: :atom, vis: :crate} =
             Enum.find(RustQ.NativeCodegen.ModuleHelpers.asts(), &(&1.name == :atom))
  end

  test "decoder helper ASTs are crate-visible and delegate required fields" do
    helpers = RustQ.NativeCodegen.DecoderHelpers.asts()

    assert %AST.Function{
             name: :required_expr,
             vis: :crate,
             body: [
               %AST.Return{
                 expr: %AST.PathCall{path: %AST.Path{parts: [:super, :decode_expr]}}
               }
             ]
           } = Enum.find(helpers, &(&1.name == :required_expr))

    assert %AST.Function{name: :required_path, vis: :crate} =
             Enum.find(helpers, &(&1.name == :required_path))

    assert %AST.Function{name: :required_string_list, vis: :crate} =
             Enum.find(helpers, &(&1.name == :required_string_list))
  end

  test "AST category predicates classify generated AST nodes" do
    assert AST.type_node?(A.unit_type())
    assert AST.type_node?(A.ref_type(:Canvas))
    refute AST.type_node?(A.var(:value))

    assert AST.expr_node?(A.var(:value))
    assert AST.expr_node?(A.call(:make_value))
    refute AST.expr_node?(A.pat(:value))

    assert AST.pat_node?(A.pat(:value))
    assert AST.pat_node?(A.some_pat(:value))
    refute AST.pat_node?(A.unit_type())
  end
end
