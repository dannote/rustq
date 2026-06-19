defmodule RustQ.Rust.AST.BuilderTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.PatternBuilder, as: P
  alias RustQ.Rust.AST.TypeBuilder, as: T

  require A

  test "builds ergonomic function argument and Rustler type nodes" do
    function = %AST.Function{
      name: :typed,
      lifetime: :a,
      args: [
        A.arg(:canvas, T.ref([:skia_safe, :Canvas])),
        A.arg(:term, T.term()),
        A.arg(:opts, T.path([:generated_opts, :TranslateOpts], lifetimes: [:a])),
        A.arg(:raw_opts, "&[(Atom, Term<'a>)]")
      ],
      returns: T.nif_result(T.unit()),
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

  test "builds slice and array type nodes" do
    assert render_type(T.slice(T.ref(:str))) == "[&str]"
    assert render_type(T.ref(T.slice(T.ref(:str)))) == "&[&str]"
    assert render_type(T.array(:u8, 4)) == "[u8; 4]"
  end

  test "splits Rust path strings into type and expression path parts" do
    assert %AST.TypePath{parts: ["paint", "Cap"]} = T.path("paint::Cap")
    assert RustQ.Rust.AST.Render.render_type(T.path("paint::Cap")) == "paint::Cap"

    assert %AST.Path{parts: ["paint", "Cap", "Butt"]} = A.path("paint::Cap::Butt")
    assert RustQ.Rust.AST.Render.render_expr(A.path("paint::Cap::Butt")) == "paint::Cap::Butt"
  end

  test "renders Rust keywords in paths as raw identifiers" do
    assert RustQ.Rust.AST.Render.render_expr(A.path([:atoms, :type])) == "atoms::r#type"
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

  test "renders function receiver arguments" do
    function = %AST.Function{
      name: :encode,
      lifetime: :a,
      args: [A.receiver(), A.arg(:env, A.type_path([:rustler, :Env], lifetimes: [:a]))],
      returns: A.type_path([:rustler, :Term], lifetimes: [:a]),
      body: [A.return(A.var(:term))]
    }

    assert RustQ.Rust.AST.Render.render_function(function) =~
             "fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a>"
  end

  test "renders lifetime-bearing impl blocks" do
    impl =
      A.impl(A.type_path(:Content),
        trait: A.type_path([:rustler, :Decoder], lifetimes: [:a]),
        lifetimes: [:a],
        items: [
          %AST.Function{
            name: :decode,
            args: [A.arg(:term, A.type_path(:Term, lifetimes: [:a]))],
            returns: A.type_path(:Self),
            body: [A.return(A.var(:todo))]
          }
        ]
      )

    assert RustQ.Rust.AST.Render.render_impl(impl) =~
             "impl<'a> rustler::Decoder<'a> for Content"
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

  test "builds tuple expressions" do
    function = %AST.Function{
      name: :pair,
      args: [],
      returns: "(i32, i32)",
      body: [A.return(A.tuple([1, 2]))]
    }

    assert RustQ.Rust.AST.Render.render_function(function) =~ "(1i64, 2i64)"
  end

  test "renders numeric literal match patterns" do
    function = %AST.Function{
      name: :compact,
      args: [A.arg(:id, :i64)],
      returns: "NifResult<Atom>",
      body: [
        A.return_stmt(
          A.match_expr(A.var(:id), [
            %AST.Arm{pattern: P.lit(1), body: [A.return_stmt(A.ok(A.atom(:clear)))]},
            A.badarg_arm()
          ])
        )
      ]
    }

    source = RustQ.Rust.AST.Render.render_function(function)

    assert source =~ "1 =>"
    assert source =~ "Ok(atoms::clear())"
  end

  test "builds semantic badarg helpers" do
    assert %AST.Path{parts: [:rustler, :Error, :BadArg]} = A.badarg()

    assert %AST.Return{expr: %AST.Err{expr: %AST.Path{parts: [:rustler, :Error, :BadArg]}}} =
             A.return_badarg()

    assert %AST.Arm{pattern: %AST.PatWildcard{}, body: [%AST.Return{}]} = A.badarg_arm()
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
              [A.return_badarg()]
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
            A.arm P.lit("Elixir.Click") do
              A.return(A.method(A.call(:decode_click, [:term]), :map, [A.path([:Event, :Click])]))
            end

            A.badarg_arm()
          end
        end
      end

    assert [
             %AST.Let{pattern: %AST.PatVar{name: :struct_name}},
             %AST.Return{expr: %AST.Match{arms: [%AST.Arm{}, %AST.Arm{}]}}
           ] = body
  end

  defp render_type(type), do: type |> RustQ.Rust.AST.Render.render_type() |> IO.iodata_to_binary()
end
