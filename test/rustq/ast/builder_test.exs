defmodule RustQ.Rust.AST.BuilderTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  require A

  test "builds ergonomic function argument and Rustler type nodes" do
    function = %AST.Function{
      name: :typed,
      lifetime: :a,
      args: [
        A.arg(:canvas, A.ref_type([:skia_safe, :Canvas])),
        A.arg(:term, A.term_type()),
        A.arg(:opts, A.type_path([:generated_opts, :TranslateOpts], lifetimes: [:a])),
        A.arg(:raw_opts, "&[(Atom, Term<'a>)]")
      ],
      returns: A.nif_result_type(A.unit_type()),
      body: [A.return(A.ok())]
    }

    source = RustQ.Rust.AST.Render.render_function(function)

    assert source =~ "fn typed<'a>("
    assert source =~ "canvas: &skia_safe::Canvas"
    assert source =~ "term: Term<'a>"
    assert source =~ "opts: generated_opts::TranslateOpts<'a>"
    assert source =~ "raw_opts: &[(Atom, Term<'a>)]"
    assert source =~ "-> NifResult<()>"
  end

  test "renders token macro expressions through native AST" do
    function = %AST.Function{
      name: :pat_none,
      args: [],
      returns: "NifResult<Pat>",
      body:
        A.block do
          A.return(A.call(:parse_pat, [A.token_macro(:quote, "None")]))
        end
    }

    assert RustQ.Rust.AST.Render.render_function(function) =~ "parse_pat(quote!(None))"
  end

  test "renders item-level Rust AST nodes through native AST" do
    source =
      RustQ.Rust.AST.Render.render_file([
        A.use([:quote, :quote]),
        A.use({[:rustler], [:Atom, :Env]}),
        A.module(
          :generated,
          [
            A.const(:NAME, "&str", "Elixir.Example", vis: :crate),
            A.macro_item("rustler::atoms! { ok }")
          ],
          vis: :crate
        )
      ])

    assert source =~ "use quote::quote;"
    assert source =~ "use rustler::{Atom, Env};"
    assert source =~ "pub(crate) mod generated"
    assert source =~ ~s|pub(crate) const NAME: &str = "Elixir.Example";|
    assert source =~ "rustler::atoms!"
  end

  test "renders if and binary operators through native AST" do
    function = %AST.Function{
      name: :expect,
      args: [left: "bool", right: "bool"],
      returns: "NifResult<()>",
      body:
        A.block do
          A.return(
            A.if_expr(
              A.and_(A.var(:left), A.eq(A.var(:right), true)),
              [A.return(A.ok())],
              [A.return(A.err(A.path([:rustler, :Error, :BadArg])))]
            )
          )
        end
    }

    source = RustQ.Rust.AST.Render.render_function(function)

    assert source =~ "if left && right == true"
    assert source =~ "Ok(())"
    assert source =~ "Err(rustler::Error::BadArg)"
  end

  test "builds structured blocks with do-end match arms" do
    body =
      A.block do
        A.let(
          :struct_name,
          A.try(
            A.method(
              A.try(A.method(:term, :map_get, [A.path_call([:atoms, :__struct__])])),
              :atom_to_string
            )
          )
        )

        A.return do
          A.match A.method(:struct_name, :as_str) do
            A.arm A.lit_pat("Elixir.Click") do
              A.return(A.method(A.call(:decode_click, [:term]), :map, [A.path([:Event, :Click])]))
            end

            A.arm A.wildcard() do
              A.return(A.err(A.path([:rustler, :Error, :BadArg])))
            end
          end
        end
      end

    assert [
             %AST.Let{pattern: %AST.PatVar{name: :struct_name}},
             %AST.Return{expr: %AST.Match{arms: [%AST.Arm{}, %AST.Arm{}]}}
           ] = body
  end
end
