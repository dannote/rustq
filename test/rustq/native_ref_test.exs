defmodule RustQ.NativeRefTest do
  use ExUnit.Case, async: true

  test "formats package-scoped native refs" do
    ref = RustQ.NativeRef.new("Canvas", "draw_rect", package: "skia-safe")

    assert ref == %RustQ.NativeRef{package: "skia-safe", target: "Canvas", member: "draw_rect"}
    assert RustQ.NativeRef.format(ref) == "skia-safe::Canvas::draw_rect"
  end

  test "formats local native refs" do
    assert RustQ.NativeRef.new("Canvas", "draw_rect") |> RustQ.NativeRef.format() ==
             "Canvas::draw_rect"
  end
end
