defmodule RustQ.Meta.InferenceTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.Inference
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  test "infers let type from downstream tuple argument element" do
    point = type(:type, "Point")
    tuple = tuple_type([point, type(:type, "Point")])

    expressions = [
      quote(do: start = decode_start(term)),
      quote(do: draw({start, stop}))
    ]

    assert Inference.infer_downstream_let_types(
             expressions,
             %{},
             callbacks(%{
               local_argument_types: fn
                 :draw, 1 -> [tuple]
                 _name, _arity -> nil
               end
             })
           ) == %{start: point}
  end

  test "infers let type from downstream receiver method call" do
    shader = type(:type, "Shader")

    expressions = [
      quote(do: shader = make_shader(term)),
      quote(do: shader.to_color())
    ]

    assert Inference.infer_downstream_let_types(
             expressions,
             %{},
             callbacks(%{
               method_receiver_type: fn
                 :to_color, 0 -> shader
                 _name, _arity -> nil
               end
             })
           ) == %{shader: shader}
  end

  test "infers Vec push argument type from known receiver type" do
    color = type(:type, "Color")
    vars = %{colors: vec_type(color)}

    expressions = [
      quote(do: color = decode_color(term)),
      quote(do: colors.push(color))
    ]

    assert Inference.infer_downstream_let_types(expressions, vars, callbacks()) == %{color: color}
  end

  defp callbacks(overrides \\ %{}) do
    Map.merge(
      %{
        return_type: fn _call -> nil end,
        local_argument_types: fn _name, _arity -> nil end,
        path_argument_types: fn _parts, _name, _arity -> nil end,
        method_argument_types: fn _target, _name, _arity -> nil end,
        target_type: fn
          %Type{rust: rust} -> rust
          nil -> nil
        end,
        method_receiver_type: fn _name, _arity -> nil end
      },
      overrides
    )
  end

  defp tuple_type(elements) do
    %Type{
      kind: :tuple,
      rust: "(" <> Enum.map_join(elements, ", ", & &1.rust) <> ")",
      ast: %AST.TypeRaw{source: "tuple"},
      meta: %{elements: elements}
    }
  end

  defp vec_type(inner) do
    %Type{
      kind: :vec,
      rust: "Vec<#{inner.rust}>",
      ast: %AST.TypeVec{inner: inner.ast},
      meta: %{inner: inner}
    }
  end

  defp type(kind, rust), do: %Type{kind: kind, rust: rust, ast: %AST.TypeRaw{source: rust}}
end
