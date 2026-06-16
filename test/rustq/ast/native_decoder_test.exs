defmodule RustQ.Rust.AST.NativeDecoderTest do
  use ExUnit.Case, async: true

  alias RustQ.Native
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  require A

  test "behavioral examples cover every current AST schema node" do
    samples =
      RustQ.Rust.AST.Schema.nodes()
      |> Map.new(fn node -> {node.name, sample_for(node.name)} end)

    assert MapSet.new(Map.keys(samples)) ==
             RustQ.Rust.AST.Schema.nodes() |> Enum.map(& &1.name) |> MapSet.new()

    for {name, ast} <- samples do
      assert is_binary(Native.render_ast(ast)), "sample for #{name} should render"
    end
  end

  test "dogfooded item and type decoders render use, module, macro, constants, structs, and enums" do
    use_source = Native.render_ast(%AST.Use{tree: "std::fmt"})

    module_source =
      Native.render_ast(%AST.Module{
        name: :generated,
        vis: :crate,
        items: [%AST.Const{name: :ANSWER, type: A.type_path(:u32), expr: A.lit(42)}]
      })

    macro_source = Native.render_ast(%AST.MacroItem{source: "type Alias = u32;"})

    const_source =
      Native.render_ast(%AST.Const{
        name: :LIMIT,
        type: %AST.TypeOption{inner: %AST.TypeRef{inner: A.type_path(:str), lifetime: :a}},
        expr: A.none(),
        vis: :crate
      })

    struct_source =
      Native.render_ast(%AST.Struct{
        name: :Holder,
        lifetime: :a,
        vis: :pub,
        fields: [
          %AST.StructField{
            name: :value,
            type: %AST.TypeRef{inner: A.type_path(:str), lifetime: :a},
            vis: :pub
          }
        ]
      })

    enum_source =
      Native.render_ast(%AST.Enum{
        name: :Maybe,
        vis: :pub,
        variants: [
          %AST.EnumVariant{name: :None},
          %AST.EnumVariant{name: :Some, tuple: [%AST.TypeVec{inner: A.type_path(:u8)}]}
        ]
      })

    assert use_source =~ "use std::fmt;"
    assert module_source =~ "pub(crate) mod generated"
    assert module_source =~ "const ANSWER: u32 = 42i64;"
    assert macro_source =~ "type Alias = u32;"
    assert const_source =~ "pub(crate) const LIMIT: Option<&'a str> = None;"
    assert struct_source =~ "pub struct Holder<'a>"
    assert struct_source =~ "pub value: &'a str"
    assert enum_source =~ "pub enum Maybe"
    assert enum_source =~ "Some(Vec<u8>)"
  end

  test "generated statement decoders render expression and return statements" do
    source =
      Native.render_ast(%AST.Function{
        name: :statements,
        args: [],
        returns: "i32",
        body:
          A.block do
            A.stmt(A.call(:side_effect))
            A.return(A.var(:value))
          end
      })

    assert source =~ "side_effect();"
    assert source =~ "value"
  end

  test "generated expression decoders render field, calls, methods, and refs" do
    source =
      Native.render_ast(%AST.Function{
        name: :exprs,
        args: [],
        returns: "NifResult<()> ",
        body:
          A.block do
            A.stmt(%AST.Field{receiver: A.var(:opts), field: :fill})
            A.stmt(A.path_call([:Rect, :from_xywh], [:x, :y, :width, :height]))
            A.stmt(A.method(:canvas, :draw_rect, [A.ref(:rect), A.mut_ref(:paint)]))
            A.return(A.ok())
          end
      })

    assert source =~ "opts.fill;"
    assert source =~ "Rect::from_xywh(x, y, width, height);"
    assert source =~ "canvas.draw_rect(&rect, &mut paint);"
  end

  test "native decoder renders mutable and typed let statements" do
    mutable_source =
      Native.render_ast(%AST.Function{
        name: :mutable_let,
        args: [],
        returns: "String",
        body:
          A.block do
            A.let_mut(:tokens, A.call(:read_tokens))
            A.return(:tokens)
          end
      })

    assert mutable_source =~ "let mut tokens = read_tokens();"

    source =
      Native.render_ast(%AST.Function{
        name: :typed_let,
        args: [],
        returns: "String",
        body:
          A.block do
            A.let(:tokens, A.call(:read_tokens), type: "String")
            A.return(:tokens)
          end
      })

    assert source =~ "let tokens: String = read_tokens();"
  end

  test "generated expression decoders render local calls, struct literals, and ok expressions" do
    source =
      Native.render_ast(%AST.Function{
        name: :more_exprs,
        args: [],
        returns: "NifResult<Rect>",
        body:
          A.block do
            A.stmt(A.call(:todo!, []))

            A.return(
              A.ok(
                A.struct([:Rect],
                  x: A.var(:x),
                  y: A.var(:y)
                )
              )
            )
          end
      })

    assert source =~ "todo!();"
    assert source =~ "Ok(Rect { x: x, y: y })"
  end

  test "generated expression decoders render literal, token macro, and binary expressions" do
    literal_source =
      Native.render_ast(%AST.Function{
        name: :literal_expr,
        args: [],
        returns: "&'static str",
        body: A.block(do: A.return(A.lit("hello")))
      })

    token_macro_source =
      Native.render_ast(%AST.Function{
        name: :token_macro_expr,
        args: [],
        returns: "TokenStream",
        body: A.block(do: A.return(A.token_macro(:quote, "None")))
      })

    binary_source =
      Native.render_ast(%AST.Function{
        name: :binary_expr,
        args: [],
        returns: "bool",
        body: A.block(do: A.return(A.and_(A.eq(:left, :right), :ok)))
      })

    assert literal_source =~ ~s|"hello"|
    assert token_macro_source =~ "quote!(None)"
    assert binary_source =~ "left == right && ok"
  end

  test "generated arm decoder renders atom guard patterns" do
    source =
      Native.render_ast(%AST.Function{
        name: :atom_guard,
        args: [value: "Atom"],
        returns: "i32",
        body:
          A.block do
            A.return do
              A.match A.var(:value) do
                A.arm %AST.PatAtomGuard{name: :ok} do
                  A.return(1)
                end

                A.arm A.wildcard() do
                  A.return(0)
                end
              end
            end
          end
      })

    assert source =~ "value if value == atoms::ok() =>"
  end

  test "generated pattern decoders render tuple, path tuple, and struct patterns" do
    source =
      Native.render_ast(%AST.Function{
        name: :pattern_exprs,
        args: [],
        returns: "i32",
        body:
          A.block do
            A.return do
              A.match A.var(:event) do
                A.arm %AST.PatTuple{patterns: [A.pat(:left), A.pat(:right)]} do
                  A.return(:left)
                end

                A.arm A.path_tuple_pat([:Event, :Click], [A.pat(:click)]) do
                  A.return(:click)
                end

                A.arm A.struct_pat([:Click], name: A.pat(:name)) do
                  A.return(:name)
                end
              end
            end
          end
      })

    assert source =~ "(left, right) =>"
    assert source =~ "Event::Click(click) =>"
    assert source =~ "Click { name: name } =>"
  end

  test "generated expression decoders render match, if, and raise atom expressions" do
    match_source =
      Native.render_ast(%AST.Function{
        name: :match_expr,
        args: [],
        returns: "NifResult<()> ",
        body:
          A.block do
            A.return do
              A.match A.var(:value) do
                A.arm A.ok_pat(:inner) do
                  A.return(A.ok(:inner))
                end

                A.arm A.err_pat(:reason) do
                  A.return(A.err(:reason))
                end
              end
            end
          end
      })

    if_source =
      Native.render_ast(%AST.Function{
        name: :if_expr,
        args: [],
        returns: "NifResult<()> ",
        body:
          A.block do
            A.return(
              A.if_expr(
                :condition,
                [A.return(A.ok())],
                [A.return(A.err(A.path([:rustler, :Error, :BadArg])))]
              )
            )
          end
      })

    raise_source =
      Native.render_ast(%AST.Function{
        name: :raise_expr,
        args: [],
        returns: "NifResult<()> ",
        body: A.block(do: A.return(%AST.NifRaiseAtom{name: :invalid}))
      })

    assert match_source =~ "match value"
    assert match_source =~ "Ok(inner)"
    assert if_source =~ "if condition"
    assert if_source =~ "Err(rustler::Error::BadArg)"
    assert raise_source =~ ~s|rustler::Error::RaiseAtom("invalid")|
  end

  test "generated expression decoders render try, tuple, some, and err expressions" do
    try_source =
      Native.render_ast(%AST.Function{
        name: :try_expr,
        args: [],
        returns: "NifResult<()> ",
        body: A.block(do: A.return(A.try(A.call(:fallible))))
      })

    tuple_source =
      Native.render_ast(%AST.Function{
        name: :tuple_expr,
        args: [],
        returns: "(i32, i32)",
        body: A.block(do: A.return(%AST.Tuple{values: [A.var(:left), A.var(:right)]}))
      })

    some_source =
      Native.render_ast(%AST.Function{
        name: :some_expr,
        args: [],
        returns: "Option<i32>",
        body: A.block(do: A.return(A.some(:value)))
      })

    err_source =
      Native.render_ast(%AST.Function{
        name: :err_expr,
        args: [],
        returns: "NifResult<()> ",
        body: A.block(do: A.return(A.err(A.path([:rustler, :Error, :BadArg]))))
      })

    assert try_source =~ "fallible()?"
    assert tuple_source =~ "(left, right)"
    assert some_source =~ "Some(value)"
    assert err_source =~ "Err(rustler::Error::BadArg)"
  end

  defp sample_for(:use), do: %AST.Use{tree: "std::fmt"}
  defp sample_for(:module), do: %AST.Module{name: :sample, items: [sample_for(:const)]}
  defp sample_for(:const), do: %AST.Const{name: :VALUE, type: A.type_path(:u32), expr: A.lit(1)}
  defp sample_for(:macro_item), do: %AST.MacroItem{source: "type Alias = u32;"}
  defp sample_for(:function), do: function_sample(:function, A.lit(1), returns: "i64")

  defp sample_for(:struct) do
    %AST.Struct{name: :Sample, fields: [%AST.StructField{name: :value, type: A.type_path(:u32)}]}
  end

  defp sample_for(:struct_field), do: sample_for(:struct)

  defp sample_for(:enum) do
    %AST.Enum{name: :SampleEnum, variants: [%AST.EnumVariant{name: :Unit}]}
  end

  defp sample_for(:enum_variant), do: sample_for(:enum)
  defp sample_for(:type_path), do: type_sample(:type_path, A.type_path(:u32))
  defp sample_for(:type_ref), do: type_sample(:type_ref, %AST.TypeRef{inner: A.type_path(:str)})

  defp sample_for(:type_option),
    do: type_sample(:type_option, %AST.TypeOption{inner: A.type_path(:u32)})

  defp sample_for(:type_result),
    do:
      type_sample(:type_result, %AST.TypeResult{
        ok: A.type_path(:u32),
        error: A.type_path(:String)
      })

  defp sample_for(:type_nif_result),
    do: type_sample(:type_nif_result, %AST.TypeNifResult{inner: A.type_path(:u32)})

  defp sample_for(:type_vec), do: type_sample(:type_vec, %AST.TypeVec{inner: A.type_path(:u8)})
  defp sample_for(:type_unit), do: type_sample(:type_unit, %AST.TypeUnit{})

  defp sample_for(:let),
    do:
      function_sample(:let_sample, %AST.Var{name: :value},
        body: [A.let(:value, A.lit(1)), A.return(:value)],
        returns: "i64"
      )

  defp sample_for(:expr_stmt),
    do: function_sample(:expr_stmt, A.call(:side_effect), statement?: true)

  defp sample_for(:return), do: function_sample(:return_sample, A.lit(1), returns: "i64")
  defp sample_for(:var), do: function_sample(:var_sample, A.var(:value), returns: "i64")

  defp sample_for(:path),
    do: function_sample(:path_sample, A.path([:Sample, :VALUE]), returns: "i64")

  defp sample_for(:field),
    do:
      function_sample(:field_sample, %AST.Field{receiver: A.var(:opts), field: :value},
        returns: "i64"
      )

  defp sample_for(:path_call),
    do: function_sample(:path_call_sample, A.path_call([:Sample, :new], []), returns: "Sample")

  defp sample_for(:method_call),
    do: function_sample(:method_call_sample, A.method(:value, :clone, []), returns: "Value")

  defp sample_for(:struct_literal),
    do: function_sample(:struct_literal_sample, A.struct([:Point], x: A.lit(1)), returns: "Point")

  defp sample_for(:local_call),
    do: function_sample(:local_call_sample, A.call(:make_value), returns: "i64")

  defp sample_for(:ref), do: function_sample(:ref_sample, A.ref(:value), returns: "&i64")

  defp sample_for(:try),
    do: function_sample(:try_sample, A.try(A.call(:fallible)), returns: "NifResult<()> ")

  defp sample_for(:tuple),
    do:
      function_sample(:tuple_sample, %AST.Tuple{values: [A.lit(1), A.lit(2)]},
        returns: "(i64, i64)"
      )

  defp sample_for(:literal), do: function_sample(:literal_sample, A.lit(1), returns: "i64")

  defp sample_for(:token_macro),
    do:
      function_sample(:token_macro_sample, A.token_macro(:quote, "None"), returns: "TokenStream")

  defp sample_for(:atom_value),
    do: function_sample(:atom_value_sample, %AST.AtomValue{name: :ok}, returns: "Atom")

  defp sample_for(:none), do: function_sample(:none_sample, A.none(), returns: "Option<i64>")

  defp sample_for(:some),
    do: function_sample(:some_sample, A.some(A.lit(1)), returns: "Option<i64>")

  defp sample_for(:ok), do: function_sample(:ok_sample, A.ok(), returns: "NifResult<()> ")

  defp sample_for(:err),
    do:
      function_sample(:err_sample, A.err(A.path([:rustler, :Error, :BadArg])),
        returns: "NifResult<()> "
      )

  defp sample_for(:nif_raise_atom),
    do:
      function_sample(:nif_raise_atom_sample, %AST.NifRaiseAtom{name: :invalid},
        returns: "NifResult<()> "
      )

  defp sample_for(:match), do: match_sample(:match_sample, A.wildcard())

  defp sample_for(:if),
    do:
      sample_for(:match)
      |> Map.put(:name, :if_sample)
      |> Map.put(:body, [
        A.return(A.if_expr(:condition, [A.return(A.lit(1))], [A.return(A.lit(0))]))
      ])

  defp sample_for(:binary_op),
    do: function_sample(:binary_op_sample, A.eq(:left, :right), returns: "bool")

  defp sample_for(:arm), do: match_sample(:arm_sample, A.wildcard())
  defp sample_for(:pat_var), do: match_sample(:pat_var_sample, A.pat(:value))
  defp sample_for(:pat_wildcard), do: match_sample(:pat_wildcard_sample, A.wildcard())
  defp sample_for(:pat_path), do: match_sample(:pat_path_sample, A.path_pat(["Option", "None"]))
  defp sample_for(:pat_literal), do: match_sample(:pat_literal_sample, A.lit_pat("ready"))
  defp sample_for(:pat_none), do: match_sample(:pat_none_sample, A.none_pat())
  defp sample_for(:pat_some), do: match_sample(:pat_some_sample, A.some_pat(:value))

  defp sample_for(:pat_atom_guard),
    do: match_sample(:pat_atom_guard_sample, %AST.PatAtomGuard{name: :ok}, args: [value: "Atom"])

  defp sample_for(:pat_tuple),
    do: match_sample(:pat_tuple_sample, %AST.PatTuple{patterns: [A.pat(:left), A.pat(:right)]})

  defp sample_for(:pat_ok), do: match_sample(:pat_ok_sample, A.ok_pat(:value))
  defp sample_for(:pat_err), do: match_sample(:pat_err_sample, A.err_pat(:reason))

  defp sample_for(:pat_path_tuple),
    do: match_sample(:pat_path_tuple_sample, A.path_tuple_pat([:Event, :Click], [A.pat(:click)]))

  defp sample_for(:pat_struct),
    do: match_sample(:pat_struct_sample, A.struct_pat([:Click], name: A.pat(:name)))

  defp type_sample(name, type) do
    %AST.Const{name: String.to_atom("#{name}_VALUE"), type: type, expr: A.lit(0)}
  end

  defp function_sample(name, expr, opts) do
    body = Keyword.get(opts, :body)
    returns = Keyword.get(opts, :returns, "()")

    body =
      cond do
        body -> body
        Keyword.get(opts, :statement?) -> [A.stmt(expr), A.return(%AST.Tuple{values: []})]
        true -> [A.return(expr)]
      end

    %AST.Function{name: name, args: Keyword.get(opts, :args, []), returns: returns, body: body}
  end

  defp match_sample(name, pattern, opts \\ []) do
    function_sample(name, A.var(:value),
      args: Keyword.get(opts, :args, []),
      returns: "i64",
      body: [
        A.return(%AST.Match{
          expr: A.var(:value),
          arms: [%AST.Arm{pattern: pattern, body: [A.return(A.lit(1))]}]
        })
      ]
    )
  end
end
