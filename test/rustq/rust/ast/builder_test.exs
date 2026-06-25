defmodule RustQ.Rust.AST.BuilderTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST.{
    Arm,
    Err,
    Function,
    Let,
    Match,
    Path,
    PatVar,
    PatWildcard,
    Render,
    Return,
    TypePath
  }

  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.PatternBuilder, as: P
  alias RustQ.Rust.AST.TypeBuilder, as: T

  require A

  test "builds ergonomic function argument and Rustler type nodes" do
    function = %Function{
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

    source = Render.render_function(function)

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
    assert %TypePath{parts: ["paint", "Cap"]} = T.path("paint::Cap")
    assert Render.render_type(T.path("paint::Cap")) == "paint::Cap"

    assert %Path{parts: ["paint", "Cap", "Butt"]} = A.path("paint::Cap::Butt")
    assert Render.render_expr(A.path("paint::Cap::Butt")) == "paint::Cap::Butt"
  end

  test "renders Rust keywords in paths as raw identifiers" do
    assert Render.render_expr(A.path([:atoms, :type])) == "atoms::r#type"
  end

  test "renders token macro expressions through native AST" do
    function = %Function{
      name: :pat_none,
      args: [],
      returns: "NifResult<Pat>",
      body:
        A.block do
          A.return(A.call(:parse_pat, [A.token_macro(:quote, "None")]))
        end
    }

    assert Render.render_function(function) =~ "parse_pat(quote!(None))"
  end

  test "renders function receiver arguments" do
    function = %Function{
      name: :encode,
      lifetime: :a,
      args: [A.receiver(), A.arg(:env, A.type_path([:rustler, :Env], lifetimes: [:a]))],
      returns: A.type_path([:rustler, :Term], lifetimes: [:a]),
      body: [A.return(A.var(:term))]
    }

    assert Render.render_function(function) =~
             "fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a>"
  end

  test "renders lifetime-bearing impl blocks" do
    impl =
      A.impl(A.type_path(:Content),
        trait: A.type_path([:rustler, :Decoder], lifetimes: [:a]),
        lifetimes: [:a],
        items: [
          %Function{
            name: :decode,
            args: [A.arg(:term, A.type_path(:Term, lifetimes: [:a]))],
            returns: A.type_path(:Self),
            body: [A.return(A.var(:todo))]
          }
        ]
      )

    assert Render.render_impl(impl) =~
             "impl<'a> rustler::Decoder<'a> for Content"
  end

  test "renders item-level Rust AST nodes through native AST" do
    source =
      Render.render_file([
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
    function = %Function{
      name: :pair,
      args: [],
      returns: "(i32, i32)",
      body: [A.return(A.tuple([1, 2]))]
    }

    assert Render.render_function(function) =~ "(1, 2)"
  end

  test "renders numeric literal match patterns" do
    function = %Function{
      name: :compact,
      args: [A.arg(:id, :i64)],
      returns: "NifResult<Atom>",
      body: [
        A.return_stmt(
          A.match_expr(A.var(:id), [
            %Arm{pattern: P.lit(1), body: [A.return_stmt(A.ok(A.atom(:clear)))]},
            A.badarg_arm()
          ])
        )
      ]
    }

    source = Render.render_function(function)

    assert source =~ "1i64 =>"
    assert source =~ "Ok(atoms::clear())"
  end

  test "renders loop and break statements" do
    function = %Function{
      name: :read_until_done,
      args: [],
      returns: "NifResult<()> ",
      body:
        A.block do
          A.loop([
            A.stmt(A.call(:step)),
            A.continue(),
            A.break()
          ])

          A.return(A.ok())
        end
    }

    source = Render.render_function(function)

    assert source =~ "loop {"
    assert source =~ "step();"
    assert source =~ "continue;"
    assert source =~ "break;"
  end

  test "renders match arm guards" do
    function = %Function{
      name: :guarded,
      args: [A.arg(:value, :i64)],
      returns: "NifResult<i64>",
      body:
        A.block do
          A.return do
            A.match A.var(:value) do
              A.arm P.var(:value), when: A.gt(:value, 0) do
                A.return(A.ok(:value))
              end

              A.badarg_arm()
            end
          end
        end
    }

    source = Render.render_function(function)

    assert source =~ "value if value > 0 =>"
    assert source =~ "Ok(value)"
  end

  test "builds semantic badarg helpers" do
    assert %Path{parts: [:rustler, :Error, :BadArg]} = A.badarg()

    assert %Return{expr: %Err{expr: %Path{parts: [:rustler, :Error, :BadArg]}}} =
             A.return_badarg()

    assert %Arm{pattern: %PatWildcard{}, body: [%Return{}]} = A.badarg_arm()
  end

  test "renders if and binary operators through native AST" do
    function = %Function{
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

    source = Render.render_function(function)

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
             %Let{pattern: %PatVar{name: :struct_name}},
             %Return{expr: %Match{arms: [%Arm{}, %Arm{}]}}
           ] = body
  end

  defp render_type(type), do: type |> Render.render_type() |> IO.iodata_to_binary()
end
