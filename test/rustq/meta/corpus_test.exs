defmodule RustQ.Meta.CorpusTest do
  use ExUnit.Case, async: false

  test "reports corpus coverage inputs" do
    coverage = RustQ.Corpus.coverage()

    assert coverage.case_count >= 12
    assert coverage.categories["control"] >= 1
    assert :unsupported_expression in coverage.unsupported_diagnostics
  end

  test "golden lowering corpus matches generated Rust" do
    assert RustQ.Corpus.cases() != []

    for {source_path, expected, actual} <- RustQ.Corpus.stale_cases() do
      flunk("""
      stale RustQ corpus output for #{Path.relative_to_cwd(source_path)}

      Expected:\n#{expected}

      Actual:\n#{actual}
      """)
    end
  end
end
