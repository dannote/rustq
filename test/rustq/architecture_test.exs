defmodule RustQ.ArchitectureTest do
  use ExUnit.Case, async: true

  @source_paths Path.wildcard("lib/**/*.ex") ++ Path.wildcard("test/**/*.exs")
  @lib_paths Path.wildcard("lib/**/*.ex")

  test "Rust path string splitting stays centralized" do
    allowed = MapSet.new(["lib/rustq/rust/ast/builder.ex", "lib/rustq/rust/ast/type_builder.ex"])

    path_split = ~r/String\.split\([^\n]*\"::\"/

    offenders =
      @source_paths
      |> Enum.reject(&MapSet.member?(allowed, &1))
      |> Enum.filter(&(File.read!(&1) =~ path_split))

    assert offenders == []
  end

  test "removed API and boilerplate patterns do not return" do
    source = Enum.map_join(@source_paths, "\n", &File.read!/1)

    forbidden = [
      "from" <> "_spec_ast",
      "native" <> "_enum(",
      "field" <> "_spec(",
      "def field" <> "_spec",
      "required" <> "_decoder_for_kind",
      "optional" <> "_decoder_for_kind",
      "defp semantic" <> "_expr",
      "defp semantic" <> "_pat",
      "defp semantic" <> "_stmt",
      "defp semantic" <> "_arm"
    ]

    Enum.each(forbidden, &refute(source =~ &1))
  end

  test "non-raw semantic helper calls stay out of production generators" do
    allowed = MapSet.new(["lib/rustq/meta/lower.ex"])
    helper_call = ~r/\b(?:expr|pat|stmt|arm)!\s*\(/

    offenders =
      @lib_paths
      |> Enum.reject(&MapSet.member?(allowed, &1))
      |> Enum.filter(&(File.read!(&1) =~ helper_call))

    assert offenders == []
  end
end
