defmodule RustQ.Spec.DeclarationsTest do
  use ExUnit.Case, async: true

  test "extracts aliases, specs, and def argument names from quoted modules" do
    quoted =
      quote do
        defmodule Sample do
          @type point :: {number(), number()}
          @type line_opts :: %{required(:from) => point(), optional(:label) => String.t()}

          @spec line(Document.t(), point(), line_opts()) :: Document.t()
          def line(document, point, opts), do: {document, point, opts}

          def helper(value), do: value
        end
      end

    assert %{aliases: aliases, specs: specs, defs: defs} = RustQ.Spec.declarations(quoted)

    assert %RustQ.Meta.Type{kind: :struct, meta: %{fields: fields}} = aliases[{:line_opts, 0}]

    assert {:from, %RustQ.Meta.Type{kind: :alias, meta: %{elixir_name: :point}}, :required} =
             List.keyfind(fields, :from, 0)

    assert [{:line, spec_args}] = specs
    assert length(spec_args) == 3
    assert defs.line == [:document, :point, :opts]
    assert defs.helper == [:value]
  end
end
