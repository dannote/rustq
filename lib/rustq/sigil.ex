defmodule RustQ.Sigil do
  @moduledoc """
  Provides the `~R` sigil for inline Rust templates.

  Use `use RustQ.Sigil` instead of importing this module directly. It excludes
  Kernel's built-in `~R` sigil and imports RustQ's version.

      defmodule MyCodegen do
        use RustQ.Sigil

        @template ~R'''
        fn answer() -> i32 { 42 }
        '''
      end
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
