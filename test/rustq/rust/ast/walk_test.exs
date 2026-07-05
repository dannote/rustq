defmodule RustQ.Rust.AST.WalkTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Walk

  test "prewalk rewrites nested AST nodes through schema fields" do
    ast = %AST.Return{
      expr: %AST.LocalCall{
        name: :consume,
        args: [%AST.Var{name: :value}]
      }
    }

    rewritten =
      Walk.prewalk(ast, fn
        %AST.Var{name: :value} = var -> %{var | name: :renamed}
        node -> node
      end)

    assert %AST.Return{expr: %AST.LocalCall{args: [%AST.Var{name: :renamed}]}} = rewritten
  end

  test "reduce traverses schema-backed nodes" do
    ast = %AST.Return{
      expr: %AST.Tuple{values: [%AST.Var{name: :left}, %AST.Var{name: :right}]}
    }

    names =
      Walk.reduce(ast, [], fn
        %AST.Var{name: name}, acc -> [name | acc]
        _node, acc -> acc
      end)

    assert Enum.sort(names) == [:left, :right]
  end

  test "postwalk traverses lists and tuple field payloads" do
    ast = %AST.StructLiteral{
      path: %AST.Path{parts: [:Point]},
      fields: [x: %AST.Var{name: :old}, y: %AST.Literal{value: 0}]
    }

    rewritten =
      Walk.postwalk(ast, fn
        %AST.Var{name: :old} = var -> %{var | name: :new}
        node -> node
      end)

    assert %AST.StructLiteral{fields: [x: %AST.Var{name: :new}, y: %AST.Literal{value: 0}]} =
             rewritten
  end
end
