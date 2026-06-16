defmodule RustQ.NativeCodegen.GeneratedASTTest do
  use ExUnit.Case, async: true

  test "generates AST helper functions through RustQ AST rendering" do
    source = RustQ.NativeCodegen.generated_ast_support()

    assert source =~ "use rustler::{Atom, Env, NifResult, Term};"
    assert source =~ "pub(crate) mod atoms"
    assert source =~ ~s|pub(crate) const FUNCTION: &str = "Elixir.RustQ.Rust.AST.Function";|
    assert source =~ "pub(crate) fn atom(env: Env, name: &str) -> NifResult<Atom>"
    assert source =~ "pub(crate) fn optional_map_get<'a>"
    assert source =~ "match term.map_get(atom(term.get_env(), key)?)"
    assert source =~ "pub(crate) fn atom_key(term: Term, key: &str) -> NifResult<String>"
    assert source =~ "pub(crate) fn struct_name(term: Term) -> NifResult<String>"
    assert source =~ "pub(crate) fn decode_ast_item(term: Term) -> NifResult<Item>"
    assert source =~ "ast_modules::FUNCTION => Ok(Item::Fn(super::decode_ast_function(term)?))"
    assert source =~ "pub(crate) fn decode_ast_type(term: Term) -> NifResult<Type>"
    assert source =~ "ast_modules::TYPE_PATH => super::decode_type_path(term)"
    assert source =~ "pub(crate) fn decode_ast_pat(term: Term) -> NifResult<Pat>"
    assert source =~ "pub(crate) fn decode_ast_stmt(term: Term) -> NifResult<Stmt>"
    assert source =~ "pub(crate) fn decode_ast_expr(term: Term) -> NifResult<Expr>"
    assert source =~ "pub(crate) fn decode_expr_tuple(term: Term) -> NifResult<Expr>"
    assert source =~ "pub(crate) fn decode_pat_var(term: Term) -> NifResult<Pat>"
  end
end
