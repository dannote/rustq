defmodule RustQ.SpecsTest do
  use ExUnit.Case, async: true

  test "derives function args and option fields from typespec declarations" do
    quoted =
      quote do
        defmodule Example do
          @type color :: atom()
          @type draw_opts :: %{
                  required(:x) => number(),
                  optional(:fill) => color()
                }

          @spec draw(term(), String.t(), draw_opts()) :: term()
          def draw(document, text, opts), do: {document, text, opts}
        end
      end

    mapper = fn
      {{:., _, [{:__aliases__, _, [:String]}, :t]}, _, []}, _types -> :string
      {:number, _, []}, _types -> :number
      {:color, _, []}, _types -> :color
      ast, types -> ast |> RustQ.Specs.expand_type(types) |> Macro.to_string()
    end

    assert [
             %{
               name: :draw,
               args: [text: :string],
               opts: [
                 [name: :x, type: :number, required: true],
                 [name: :fill, type: :color, required: false]
               ]
             }
           ] = RustQ.Specs.from_quoted(quoted, type_mapper: mapper)
  end

  test "default type mapper returns expanded type strings" do
    quoted =
      quote do
        defmodule Example do
          @type opts :: %{optional(:enabled) => boolean()}
          @spec toggle(term(), opts()) :: term()
          def toggle(document, opts), do: {document, opts}
        end
      end

    assert [%{opts: [[name: :enabled, type: "boolean()", required: false]]}] =
             RustQ.Specs.from_quoted(quoted)
  end
end
