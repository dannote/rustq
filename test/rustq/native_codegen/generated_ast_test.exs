defmodule RustQ.NativeCodegen.GeneratedASTTest do
  use ExUnit.Case, async: true

  test "generates AST helper functions through RustQ AST rendering" do
    source = RustQ.NativeCodegen.generated_ast_support()

    assert source =~ "use rustler::{Atom, Env, NifResult, Term};"
    assert source =~ "pub(crate) mod atoms"
    assert source =~ ~s|pub(crate) const FUNCTION: &str = "Elixir.RustQ.Rust.AST.Function";|
    refute source =~ ~s|pub(crate) const ARM: &str = "Elixir.RustQ.Rust.AST.Arm";|
    assert source =~ "pub(crate) fn atom(env: Env, name: &str) -> NifResult<Atom>"
    assert source =~ "pub(crate) fn required_field<'a>"
    assert source =~ "pub(crate) fn optional_map_get<'a>"
    assert source =~ "match term.map_get(atom(term.get_env(), key)?)"
    assert source =~ "pub(crate) fn atom_key<'a>(term: Term<'a>, key: &str) -> NifResult<String>"

    assert source =~
             "pub(crate) fn optional_atom_key<'a>(term: Term<'a>, key: &str) -> NifResult<Option<String>>"

    assert source =~ "pub(crate) fn is_nil<'a>(term: Term<'a>) -> NifResult<bool>"
    assert source =~ "pub(crate) fn struct_name<'a>(term: Term<'a>) -> NifResult<String>"

    assert source =~
             "pub(crate) fn expect_struct<'a>(term: Term<'a>, expected: &str) -> NifResult<()>"

    assert source =~ "pub(crate) fn decode_ast_item(term: Term) -> NifResult<Item>"
    assert source =~ "ast_modules::FUNCTION => Ok(Item::Fn(decode_ast_function(term)?))"
    assert source =~ "pub(crate) fn decode_ast_type(term: Term) -> NifResult<Type>"
    assert source =~ "ast_modules::TYPE_PATH => decode_type_path(term)"
    assert source =~ "pub(crate) fn decode_ast_pat(term: Term) -> NifResult<Pat>"
    assert source =~ "pub(crate) fn decode_ast_stmt(term: Term) -> NifResult<Stmt>"
    assert source =~ "pub(crate) fn decode_ast_expr(term: Term) -> NifResult<Expr>"
    assert source =~ "pub(crate) fn decode_pat_some<'a>(term: Term<'a>) -> NifResult<Pat>"
    assert source =~ "super::parse_syn::<Pat>(quote!(Some(# pat)))"
    assert source =~ "pub(crate) fn decode_expr_try<'a>(term: Term<'a>) -> NifResult<Expr>"
    assert source =~ "super::parse_syn::<Expr>(quote!(# expr ?))"
    assert source =~ "pub(crate) fn decode_stmt_return<'a>(term: Term<'a>) -> NifResult<Stmt>"
    assert source =~ "Ok(Stmt::Expr(expr, None))"
    assert source =~ "pub(crate) fn decode_expr_none<'a>(_term: Term<'a>) -> NifResult<Expr>"
    assert source =~ "super::parse_syn::<Expr>(quote!(None))"
    assert source =~ "pub(crate) fn decode_expr_tuple<'a>(term: Term<'a>) -> NifResult<Expr>"
    assert source =~ "pub(crate) fn decode_pat_wildcard<'a>(_term: Term<'a>) -> NifResult<Pat>"
    assert source =~ "super::parse_syn::<Pat>(quote!(_))"
    assert source =~ "pub(crate) fn decode_pat_var<'a>(term: Term<'a>) -> NifResult<Pat>"
    assert source =~ "super::format_ident_value(atom_key(term, \"name\")?)"
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
