defmodule RustQ.Reach.Smells.DynamicRawRustEscape do
  @moduledoc """
  Detects dynamic values passed to raw Rust escape APIs.

  Raw escape APIs must receive a literal source fragment so the escape remains
  local, auditable, and parser-validated. Dynamic interpolation or composition
  should instead be represented through RustQ AST, `defrust`, or Elixir macros.
  """

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @kind :rustq_dynamic_raw_rust_escape
  @raw_functions [:raw_expr!, :raw_pat!, :raw_stmt!, :raw_arm!]
  @raw_methods [:raw, :item, :impl_item, :stmt, :expr, :arm, :macro_item]
  @explicit_boundaries [
    "lib/rustq.ex",
    "lib/rustq/rust/ast/builder.ex",
    "lib/rustq/rustler/atom.ex",
    "lib/rustq/rustler/nif.ex"
  ]

  @impl true
  def kinds, do: [@kind]

  defp scan_ast(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        {node, dynamic_escape_findings(node, file) ++ findings}
      end)

    Enum.reverse(findings)
  end

  defp dynamic_escape_findings(node, file) do
    with false <- explicit_boundary?(file),
         {:ok, meta, source} <- raw_escape(node),
         false <- literal_source?(source) do
      [
        Finding.new(
          kind: @kind,
          message:
            "dynamic raw Rust escape; use RustQ AST, defrust, or a literal parser-validated escape",
          location: "#{file}:#{meta[:line] || 0}",
          evidence: Macro.to_string(source)
        )
      ]
    else
      _literal_or_not_escape -> []
    end
  end

  defp raw_escape({name, meta, [source]}) when name in @raw_functions, do: {:ok, meta, source}

  defp raw_escape({{:., meta, [_receiver, function]}, _call_meta, [source]})
       when function in @raw_methods,
       do: {:ok, meta, source}

  defp raw_escape(_node), do: :error

  defp explicit_boundary?(file), do: file in @explicit_boundaries

  defp literal_source?(source) when is_binary(source), do: true
  defp literal_source?({:__block__, _meta, [source]}) when is_binary(source), do: true
  defp literal_source?(_source), do: false
end
