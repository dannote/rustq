defmodule RustQ.Rust.ASTBuilderTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  require A

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
