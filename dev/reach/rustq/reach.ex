defmodule RustQ.Reach do
  @moduledoc """
  Reach plugin for RustQ dogfooding rules.

  The plugin contributes smell checks that encode RustQ's Rusty-Elixir doctrine
  as architecture tooling instead of ad hoc source-grep tests.
  """

  @behaviour Reach.Plugin

  @impl true
  def analyze(_all_nodes, _opts), do: []

  @impl true
  def smell_checks do
    [
      RustQ.Reach.Smells.RawRustEscape,
      RustQ.Reach.Smells.LowLevelControlFlow,
      RustQ.Reach.Smells.TrivialDefrustWrapper,
      RustQ.Reach.Smells.BlocklessDefrustmod
    ]
  end
end
