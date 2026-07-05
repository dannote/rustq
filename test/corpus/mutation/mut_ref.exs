defmodule RustQ.Corpus.Mutation.MutRef do
  @moduledoc "auto-borrowed mutable arguments mark local bindings mutable."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec touch(R.mut_ref(R.u32())) :: R.unit()
  defrust touch(_value) do
    :ok
  end

  @spec run(R.u32()) :: R.unit()
  defrust run(value) do
    local = value
    touch(local)
    :ok
  end
end
