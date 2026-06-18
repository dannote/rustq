defmodule RustQ.SpecTest do
  use ExUnit.Case, async: true

  test "lowers quoted spec types" do
    assert RustQ.Spec.type(quote(do: RustQ.Type.ref(SkiaSafe.Canvas.t()))).rust ==
             "&skia_safe::Canvas"
  end

  test "lowers quoted enum intent types structurally" do
    assert %RustQ.Meta.Type{kind: :enum, rust: "stroke_cap", meta: %{enum: :stroke_cap}} =
             RustQ.Spec.type(quote(do: RustQ.Type.enum(:stroke_cap)))
  end

  test "lowers quoted tuple types structurally" do
    assert %RustQ.Meta.Type{kind: :tuple, rust: "(f64, f64)", meta: %{elements: elements}} =
             RustQ.Spec.type(quote(do: {number(), number()}))

    assert [%RustQ.Meta.Type{kind: :f64}, %RustQ.Meta.Type{kind: :f64}] = elements
  end

  test "lowers BEAM abstract remote types" do
    canvas = {:remote_type, 1, [{:atom, 1, SkiaSafe.Canvas}, {:atom, 1, :t}, []]}

    assert RustQ.Spec.type(canvas).rust == "skia_safe::Canvas"
  end

  test "builds aliases from quoted type declarations" do
    aliases =
      RustQ.Spec.aliases([
        {:type, quote(do: point :: {number(), number()}), 1},
        {:type, quote(do: rect_opts :: %{required(:x) => number(), optional(:point) => point()}),
         2}
      ])

    assert %RustQ.Meta.Type{kind: :struct, rust: "RectOpts", meta: %{fields: fields}} =
             aliases[{:rect_opts, 0}]

    assert {:x, %RustQ.Meta.Type{rust: "f64"}, :required} = List.keyfind(fields, :x, 0)

    assert {:point, %RustQ.Meta.Type{kind: :alias, rust: "Point"}, :optional} =
             List.keyfind(fields, :point, 0)
  end

  test "builds aliases from BEAM abstract type declarations" do
    types = [
      type: {:point, {:type, 1, :tuple, [{:type, 1, :number, []}, {:type, 1, :number, []}]}, []},
      type:
        {:rect_opts,
         {:type, 1, :map,
          [
            {:type, 1, :map_field_exact, [{:atom, 1, :x}, {:type, 1, :number, []}]},
            {:type, 1, :map_field_assoc,
             [
               {:atom, 1, :label},
               {:remote_type, 1, [{:atom, 1, String}, {:atom, 1, :t}, []]}
             ]},
            {:type, 1, :map_field_assoc, [{:atom, 1, :point}, {:user_type, 1, :point, []}]}
          ]}, []}
    ]

    aliases = RustQ.Spec.aliases(types)

    assert %RustQ.Meta.Type{kind: :struct, rust: "RectOpts", meta: %{fields: fields}} =
             aliases[{:rect_opts, 0}]

    assert {:x, %RustQ.Meta.Type{rust: "f64"}, :required} = List.keyfind(fields, :x, 0)
    assert {:label, %RustQ.Meta.Type{rust: "String"}, :optional} = List.keyfind(fields, :label, 0)

    assert {:point, %RustQ.Meta.Type{kind: :alias, rust: "Point"}, :optional} =
             List.keyfind(fields, :point, 0)
  end
end
