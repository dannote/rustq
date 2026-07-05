defmodule RustQ.Corpus.Mutation.MutRef do
  @moduledoc "mut_ref marks local bindings mutable."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec touch(R.mut_ref(R.u32())) :: R.unit()
  defrust touch(_value) do
    :ok
  end

  @spec run(R.u32()) :: R.unit()
  defrust run(value) do
    local = value
    touch(mut_ref(local))
    :ok
  end
end
