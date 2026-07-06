defmodule RustQ.Binding.IndexTest do
  use ExUnit.Case, async: true

  alias RustQ.Binding.Callable
  alias RustQ.Binding.Index
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  test "indexes free functions by name and arity" do
    return = type(:result, "Result<Foo, Error>")
    callable = %Callable{name: "decode", kind: :function, args: [arg("term")], returns: return}
    index = Index.new([callable])

    assert Index.get(index, nil, :decode, 1) == callable
    assert Index.return_type(index, nil, "decode", 1) == return
    assert Index.argument_types(index, nil, "decode", 1) == [type(:type, "Term")]
    assert Index.return_type(index, nil, "decode", 2) == nil
  end

  test "indexes methods by Rust arity and receiverless call arity" do
    return = type(:ref, "&Self")

    callable = %Callable{
      name: "draw_rect",
      kind: :method,
      target: "Canvas",
      args: [arg("self"), arg("rect")],
      returns: return
    }

    index = Index.new([callable])

    assert Index.get(index, "Canvas", "draw_rect", 2) == callable
    assert Index.get(index, "Canvas", "draw_rect", 1) == callable
    assert Index.return_type(index, :Canvas, :draw_rect, 1) == return
    assert Index.argument_types(index, :Canvas, :draw_rect, 1) == [type(:type, "Term")]
    assert Index.method_targets(index, :draw_rect, 1) == ["Canvas"]
  end

  test "indexes qualified targets by their last path segment" do
    callable = %Callable{
      name: "new_copy",
      kind: :function,
      target: "skia_safe::Data",
      args: [arg("data")],
      returns: nil
    }

    index = Index.new([callable])

    assert Index.argument_types(index, :Data, :new_copy, 1) == [type(:type, "Term")]
  end

  test "returns unique method receiver targets by receiverless call arity" do
    index =
      Index.new([
        %Callable{
          name: "to_shader",
          kind: :method,
          target: "Image",
          args: [arg("self")],
          returns: nil
        },
        %Callable{
          name: "to_shader",
          kind: :method,
          target: "Picture",
          args: [arg("self"), arg("rect")],
          returns: nil
        }
      ])

    assert Index.method_targets(index, :to_shader, 0) == ["Image"]
    assert Index.method_targets(index, :to_shader, 1) == ["Picture"]
  end

  defp arg(name), do: %{name: name, type: type(:type, "Term"), syn: nil}

  defp type(kind, rust), do: %Type{kind: kind, rust: rust, ast: %AST.TypeRaw{source: rust}}
end
