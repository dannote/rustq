defmodule RustQ.Clippy do
  @moduledoc """
  Idiomatic Rusty-Elixir helpers for Clippy lint attribute paths.

  Use these through `use RustQ.Meta`, which aliases this module as `Clippy`:

      @allow Clippy.redundant_field_names
      defrust build(value) do
        ...
      end

  The helper returns RustQ path metadata that renders as
  `#[allow(clippy::redundant_field_names)]`.
  """

  alias RustQ.Rust.AST

  @doc """
  Returns the `clippy::redundant_field_names` lint path.
  """
  @spec redundant_field_names() :: AST.Path.t()
  def redundant_field_names do
    lint(:redundant_field_names)
  end

  @doc """
  Returns a Clippy lint path for `name`.
  """
  @spec lint(atom() | String.t()) :: AST.Path.t()
  def lint(name) do
    %AST.Path{parts: [:clippy, name]}
  end
end
