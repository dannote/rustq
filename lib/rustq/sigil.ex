defmodule RustQ.Sigil do
  @moduledoc """
  Rust source sigil helpers.

  Use this module instead of importing it directly so Kernel's built-in `~R`
  sigil is excluded for the caller.
  """

  defmacro __using__(_opts) do
    quote do
      import Kernel, except: [sigil_R: 2]
      import RustQ.Sigil, only: [sigil_R: 2]
    end
  end

  @doc """
  Returns Rust source as a binary.
  """
  defmacro sigil_R({:<<>>, _meta, [source]}, _modifiers), do: source
end
