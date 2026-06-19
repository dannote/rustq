defmodule RustQ.ArchitectureTest do
  use ExUnit.Case, async: true

  @source_paths Path.wildcard("lib/**/*.ex") ++ Path.wildcard("test/**/*.exs")

  test "removed API and boilerplate patterns do not return" do
    source = Enum.map_join(@source_paths, "\n", &File.read!/1)

    forbidden = [
      "from" <> "_spec_ast",
      "native" <> "_enum(",
      "field" <> "_spec(",
      "def field" <> "_spec",
      "required" <> "_decoder_for_kind",
      "optional" <> "_decoder_for_kind"
    ]

    Enum.each(forbidden, &refute(source =~ &1))
  end
end
