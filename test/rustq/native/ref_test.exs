defmodule RustQ.Native.RefTest do
  use ExUnit.Case, async: true

  alias RustQ.Native.Ref

  test "formats package-scoped native refs" do
    ref = Ref.new("Canvas", "draw_rect", package: "skia-safe")

    assert ref == %Ref{package: "skia-safe", target: "Canvas", member: "draw_rect"}
    assert Ref.format(ref) == "skia_safe::Canvas::draw_rect"
  end

  test "formats local native refs" do
    assert Ref.new("Canvas", "draw_rect") |> Ref.format() ==
             "Canvas::draw_rect"
  end
end
