defmodule RustQ.NativeCodegen.GeneratedASTTest do
  use ExUnit.Case, async: true

  test "generates AST support modules and dispatch functions" do
    source = RustQ.NativeCodegen.generated_ast_support()

    assert source =~ "use rustler::{Atom, Env, NifResult, Term};"
    assert source =~ "pub(crate) mod atoms"
    assert source =~ "pub(crate) mod ast_modules"
    assert source =~ "pub(crate) fn decode_ast_item(term: Term) -> NifResult<Item>"
    assert source =~ "pub(crate) fn decode_ast_type(term: Term) -> NifResult<Type>"
    assert source =~ "pub(crate) fn decode_ast_pat(term: Term) -> NifResult<Pat>"
    assert source =~ "pub(crate) fn decode_ast_stmt(term: Term) -> NifResult<Stmt>"
    assert source =~ "pub(crate) fn decode_ast_expr(term: Term) -> NifResult<Expr>"
    assert source =~ ~s|pub(crate) const FUNCTION: &str = "Elixir.RustQ.Rust.AST.Function";|
    refute source =~ ~s|pub(crate) const ARM: &str = "Elixir.RustQ.Rust.AST.Arm";|
  end

  test "dogfooded decoder modules cover generated decoder categories" do
    decoder_names =
      RustQ.NativeCodegen.Decoders.asts()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    expected_expr_decoders =
      RustQ.Rust.AST.Schema.nodes(:expr)
      |> Enum.map(&String.to_atom("decode_expr_#{&1.name}"))

    expected_stmt_decoders =
      RustQ.Rust.AST.Schema.nodes(:stmt)
      |> Enum.map(&String.to_atom("decode_stmt_#{&1.name}"))

    expected_pat_decoders =
      RustQ.Rust.AST.Schema.nodes(:pat)
      |> Enum.reject(&(&1.name == :pat_atom_guard))
      |> Enum.map(&String.to_atom("decode_#{&1.name}"))

    expected_type_decoders = [
      :decode_type_path,
      :decode_type_unit,
      :decode_type_option,
      :decode_type_result,
      :decode_type_nif_result,
      :decode_type_vec
    ]

    expected_item_decoders = [
      :decode_ast_use,
      :decode_ast_module,
      :decode_ast_const,
      :decode_ast_function,
      :decode_ast_struct,
      :decode_ast_macro_item,
      :decode_ast_enum,
      :decode_struct_field,
      :decode_enum_variant
    ]

    for decoder <-
          expected_item_decoders ++
            expected_type_decoders ++
            expected_expr_decoders ++ expected_stmt_decoders ++ expected_pat_decoders do
      assert MapSet.member?(decoder_names, decoder), "missing dogfooded decoder #{decoder}"
    end
  end
end
