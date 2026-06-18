defmodule RustQ.Syn.Doc do
  @moduledoc "Utilities for rendering Rust doc comments for downstream docs."

  @doc """
  Renders Rust doc comment lines as Markdown suitable for consumer docs.

  This keeps the transformation structural and conservative: it only normalizes
  Rust intra-doc code links into Markdown code spans and joins lines.
  """
  @spec markdown([String.t()]) :: String.t()
  def markdown(lines) when is_list(lines) do
    lines
    |> Enum.map(&line/1)
    |> Enum.join("\n")
  end

  @doc "Normalizes one Rust doc line for Markdown output."
  @spec line(String.t()) :: String.t()
  def line(line) when is_binary(line) do
    line
    |> String.replace(~r/\[`(?:crate::)?([^\]]+)`\]/, "`\\1`")
  end
end
