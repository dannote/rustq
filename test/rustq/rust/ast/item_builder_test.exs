defmodule RustQ.Rust.AST.ItemBuilderTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  import RustQ.Rust.AST.ItemBuilder

  require A
  require RustQ.Rust.AST.ItemBuilder

  test "builds function items with block bodies" do
    item =
      function :hello,
        vis: :crate,
        args: [value: "i32"],
        returns: "NifResult<i32>" do
        A.let(:next, A.call(:increment, [:value]))
        A.return(A.ok(:next))
      end

    assert %AST.Function{
             name: :hello,
             vis: :crate,
             args: [%AST.FunctionArg{name: :value, type: "i32"}],
             returns: "NifResult<i32>",
             body: [%AST.Let{}, %AST.Return{}]
           } = item
  end
end
