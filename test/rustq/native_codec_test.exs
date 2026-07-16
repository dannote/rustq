defmodule RustQ.NativeCodecTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.PatternBuilder, as: P
  alias RustQ.Rust.AST.TypeBuilder, as: T

  test "renders structural union codec implementations" do
    decoder = %AST.Function{
      name: :decode,
      args: A.function_args(term: T.term(:a)),
      returns: T.nif_result(T.path(:Shape)),
      body: [
        A.if_let(
          P.ok(:value),
          A.method(:term, :decode, [], generics: [T.path(:Circle)]),
          [A.early_return(A.ok(A.path_call([:Shape, :Circle], [:value])))]
        ),
        A.return_stmt(A.err(A.path([:rustler, :Error, :BadArg])))
      ]
    }

    encoder = %AST.Function{
      name: :encode,
      args: [A.receiver(), A.arg(:env, T.path(:Env, lifetimes: [:a]))],
      returns: T.term(:a),
      lifetimes: [:a],
      body: [
        A.return_stmt(%AST.Match{
          expr: A.expr(:self),
          arms: [
            %AST.Arm{
              pattern: P.path_tuple([:Shape, :Circle], [:value]),
              body: [A.return_stmt(A.method(:value, :encode, [:env]))]
            }
          ]
        })
      ]
    }

    decoder_impl =
      A.impl(T.path(:Shape),
        trait: T.path([:rustler, :Decoder], lifetimes: [:a]),
        lifetimes: [:a],
        items: [decoder]
      )

    encoder_impl = A.impl(T.path(:Shape), trait: [:rustler, :Encoder], items: [encoder])

    assert Rust.render(decoder) =~ "fn decode(term: Term<'a>) -> NifResult<Shape>"
    assert Rust.render(encoder) =~ "fn encode<'a>(&self, env: Env<'a>) -> Term<'a>"
    assert Rust.render(decoder_impl) =~ "impl<'a> rustler::Decoder<'a> for Shape"
    assert Rust.render(encoder_impl) =~ "impl rustler::Encoder for Shape"
  end
end
