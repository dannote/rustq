defmodule RustQ.Rust.AST.BuilderTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  require A

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

    assert AST.render_function_native(function) =~ "parse_pat(quote!(None))"
  end

  test "renders item-level Rust AST nodes through native AST" do
    source =
      AST.render_file_native([
        A.use([:quote, :quote]),
        A.use("rustler::{Atom, Env}"),
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

    source = AST.render_function_native(function)

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
