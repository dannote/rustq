defmodule RustQ.Rust.AST.SchemaTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST.Schema

  test "derives nodes from AST modules and their typespecs" do
    nodes = Schema.nodes()

    assert function = Enum.find(nodes, &(&1.module == RustQ.Rust.AST.Function))
    assert function.name == :function
    assert function.rust_const == :FUNCTION
    assert function.rust_module == "Elixir.RustQ.Rust.AST.Function"
    assert function.category == :item
    assert {:body, _type} = List.keyfind(function.fields, :body, 0)
    refute List.keymember?(function.fields, :__struct__, 0)
  end

  test "filters nodes by category" do
    assert Enum.any?(Schema.nodes(:expr), &(&1.module == RustQ.Rust.AST.Var))
    refute Enum.any?(Schema.nodes(:expr), &(&1.module == RustQ.Rust.AST.Function))
  end
end
