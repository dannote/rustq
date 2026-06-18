defmodule RustQ.Meta.TypeTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.Type

  test "maps fitting built-in Elixir types to Rust/Rustler types" do
    assert RustQ.Spec.type(quote(do: atom())).rust == "Atom"
    assert RustQ.Spec.type(quote(do: term())).rust == "Term<'a>"
    assert RustQ.Spec.type(quote(do: boolean())).rust == "bool"
    assert RustQ.Spec.type(quote(do: integer())).rust == "i64"
    assert RustQ.Spec.type(quote(do: float())).rust == "f64"
    assert RustQ.Spec.type(quote(do: number())).rust == "f64"
    assert RustQ.Spec.type(quote(do: binary())).rust == "Vec<u8>"
  end

  test "parses external Rust module types from ordinary remote types" do
    assert RustQ.Spec.type(quote(do: GeneratedOpts.OvalOpts.t(R.lifetime(:a)))).rust ==
             "generated_opts::OvalOpts<'a>"

    assert RustQ.Spec.type(quote(do: R.ref(SkiaSafe.Canvas.t()))).rust ==
             "&skia_safe::Canvas"

    assert RustQ.Spec.type(quote(do: R.slice({R.atom(), R.term()}))).rust ==
             "&[(Atom, Term<'a>)]"
  end

  test "categorizes lowered types semantically" do
    number = RustQ.Spec.type(quote(do: number()))
    integer = RustQ.Spec.type(quote(do: integer()))
    boolean = RustQ.Spec.type(quote(do: boolean()))
    atom = RustQ.Spec.type(quote(do: atom()))
    string = RustQ.Spec.type(quote(do: String.t()))
    tuple = RustQ.Spec.type(quote(do: {number(), integer()}))
    external = RustQ.Spec.type(quote(do: Skia.Path.t()))

    assert Type.category(number) == :number
    assert Type.category(integer) == :integer
    assert Type.category(boolean) == :boolean
    assert Type.category(atom) == :atom
    assert Type.category(string) == :string
    assert {:tuple, [^number, ^integer]} = Type.category(tuple)
    assert Type.category(external) == :type
    assert Type.external?(external, Skia.Path, :t)
    refute Type.external?(external, Skia.Paint, :t)
  end

  test "keeps explicit Rust path marker as a low-level escape hatch" do
    assert RustQ.Spec.type(quote(do: R.path({:generated_opts, :OvalOpts}, R.lifetime(:a)))).rust ==
             "generated_opts::OvalOpts<'a>"
  end

  test "keeps external Elixir origin metadata" do
    assert %Type{
             rust: "skia_safe::Canvas",
             meta: %{elixir_module: SkiaSafe.Canvas, elixir_type: :t, elixir_args: []}
           } = RustQ.Spec.type(quote(do: SkiaSafe.Canvas.t()))

    assert %Type{
             rust: "skia_safe::Canvas::borrowed",
             meta: %{elixir_module: SkiaSafe.Canvas, elixir_type: :borrowed, elixir_args: []}
           } = RustQ.Spec.type(quote(do: SkiaSafe.Canvas.borrowed()))
  end

  test "keeps external t aliases as direct Rust identifiers" do
    assert RustQ.Spec.type(quote(do: ItemConst.t())).rust == "ItemConst"
    assert RustQ.Spec.type(quote(do: ItemStruct.t())).rust == "ItemStruct"
    assert RustQ.Spec.type(quote(do: Field.t())).rust == "Field"
    assert RustQ.Spec.type(quote(do: RustQ.Some.External.t())).rust == "External"

    assert RustQ.Spec.type(quote(do: RustQ.Type.nif_result(ItemEnum.t()))).rust ==
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
               {:vec, 1},
               {:path, 1},
               {:path, 2},
               {:lifetime, 1},
               {:slice, 1},
               {:raw, 1}
             ]),
             types
           )
  end
end
