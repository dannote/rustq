defmodule RustQ.NativeCodegenTest do
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
  end
end
