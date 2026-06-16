defmodule RustQ.Meta.TypeTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.Type

  test "maps fitting built-in Elixir types to Rust/Rustler types" do
    assert Type.from_spec_ast(quote(do: atom())).rust == "Atom"
    assert Type.from_spec_ast(quote(do: term())).rust == "Term<'a>"
    assert Type.from_spec_ast(quote(do: boolean())).rust == "bool"
    assert Type.from_spec_ast(quote(do: integer())).rust == "i64"
    assert Type.from_spec_ast(quote(do: float())).rust == "f64"
    assert Type.from_spec_ast(quote(do: binary())).rust == "Vec<u8>"
  end

  test "keeps external t aliases as direct Rust identifiers" do
    assert Type.from_spec_ast(quote(do: ItemConst.t())).rust == "ItemConst"
    assert Type.from_spec_ast(quote(do: ItemStruct.t())).rust == "ItemStruct"
    assert Type.from_spec_ast(quote(do: Field.t())).rust == "Field"
    assert Type.from_spec_ast(quote(do: RustQ.Some.External.t())).rust == "External"

    assert Type.from_spec_ast(quote(do: RustQ.Type.nif_result(ItemEnum.t()))).rust ==
             "NifResult<ItemEnum>"
  end

  test "exports non-reserved Rust vocabulary as Elixir types" do
    {:docs_v1, _annotation, _beam_language, _format, _module_doc, _metadata, docs} =
      Code.fetch_docs(RustQ.Type)

    types =
      docs
      |> Enum.filter(&match?({{:type, _, _}, _, _, _, _}, &1))
      |> MapSet.new(fn {{:type, name, arity}, _line, _signature, _doc, _metadata} ->
        {name, arity}
      end)

    assert MapSet.subset?(
             MapSet.new([
               {:unit, 0},
               {:u8, 0},
               {:u32, 0},
               {:i64, 0},
               {:f32, 0},
               {:f64, 0},
               {:ref, 1},
               {:mut_ref, 1},
               {:option, 1},
               {:result, 2},
               {:nif_result, 1},
               {:vec, 1}
             ]),
             types
           )
  end
end
