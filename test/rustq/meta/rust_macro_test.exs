defmodule RustQ.Meta.RustMacroTest do
  use ExUnit.Case, async: true

  alias RustQ.Diagnostic
  alias RustQ.Meta.RustMacro
  alias RustQ.Meta.RustMacro.Definition

  test "normalizes defrustmacro arguments into Rust fragments" do
    [definition] =
      RustMacro.definitions([
        {quote(do: field(term, name, type: :ty)), quote(do: term), nil}
      ])

    assert %Definition{
             name: :field,
             args: [term: :expr, name: :expr, type: :ty],
             rust_module: nil
           } = definition
  end

  test "indexes macro definitions and rejects duplicates" do
    [definition] = RustMacro.definitions([{quote(do: identity(value)), quote(do: value), nil}])

    assert %{identity: ^definition} = RustMacro.index!([definition])

    assert_raise Diagnostic.Error, ~r/duplicate defrustmacro identity/, fn ->
      RustMacro.index!([definition, definition])
    end
  end

  test "rejects duplicate argument names" do
    assert_raise Diagnostic.Error, ~r/duplicate argument value in defrustmacro bad/, fn ->
      RustMacro.definitions([{quote(do: bad(value, value)), quote(do: value), nil}])
    end
  end

  test "emits compact macro_rules items from Rusty-Elixir bodies" do
    [definition] =
      RustMacro.definitions([
        {quote(do: identity(value)), quote(do: value), [:helpers]}
      ])

    [item] = RustMacro.items([definition], %{}, __ENV__, [], RustMacro.index!([definition]))

    assert item.rust_module == [:helpers]
    assert item.ast.source =~ "macro_rules! identity"
    assert item.ast.source =~ "$value:expr"
    assert item.ast.source =~ "$value"
    refute item.ast.source =~ "$value "
  end
end
