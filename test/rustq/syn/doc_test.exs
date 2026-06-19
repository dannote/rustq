defmodule RustQ.Syn.DocTest do
  use ExUnit.Case, async: true

  alias RustQ.Syn.Doc

  test "normalizes Rust intra-doc code links" do
    assert Doc.line("Draws [`Rect`] using [`crate::paint::Style`].") ==
             "Draws `Rect` using `paint::Style`."
  end

  test "renders Markdown from doc lines" do
    assert Doc.markdown(["Draws [`Rect`] rect.", "", "- `paint` [`Paint`]"]) ==
             "Draws `Rect` rect.\n\n- `paint` `Paint`"
  end
end
