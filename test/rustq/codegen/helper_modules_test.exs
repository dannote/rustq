defmodule RustQ.Codegen.HelperModulesTest do
  use ExUnit.Case, async: true

  alias RustQ.Codegen.DecoderHelpers
  alias RustQ.Codegen.Helpers
  alias RustQ.Codegen.ModuleHelpers
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.Function
  alias RustQ.Rust.AST.Path
  alias RustQ.Rust.AST.PathCall
  alias RustQ.Rust.AST.PatternBuilder, as: P
  alias RustQ.Rust.AST.Return
  alias RustQ.Rust.AST.TypeBuilder, as: T

  test "native defrust modules expose crate-visible ASTs" do
    assert %Function{name: :required_field, vis: :crate} =
             Enum.find(Helpers.asts(), &(&1.name == :required_field))

    assert %Function{name: :atom, vis: :crate} =
             Enum.find(ModuleHelpers.asts(), &(&1.name == :atom))
  end

  test "decoder helper ASTs are crate-visible and delegate required fields" do
    helpers = DecoderHelpers.asts()

    assert %Function{
             name: :required_expr,
             vis: :crate,
             body: [
               %Return{
                 expr: %PathCall{path: %Path{parts: [:super, :decode_expr]}}
               }
             ]
           } = Enum.find(helpers, &(&1.name == :required_expr))

    assert %AST.Function{name: :required_path, vis: :crate} =
             Enum.find(helpers, &(&1.name == :required_path))

    assert %AST.Function{name: :required_string_list, vis: :crate} =
             Enum.find(helpers, &(&1.name == :required_string_list))
  end

  test "AST category predicates classify generated AST nodes" do
    assert AST.type_node?(T.unit())
    assert AST.type_node?(T.ref(:Canvas))
    refute AST.type_node?(A.var(:value))

    assert AST.expr_node?(A.var(:value))
    assert AST.expr_node?(A.call(:make_value))
    refute AST.expr_node?(A.pat(:value))

    assert AST.pat_node?(A.pat(:value))
    assert AST.pat_node?(P.some(:value))
    refute AST.pat_node?(T.unit())
  end
end
