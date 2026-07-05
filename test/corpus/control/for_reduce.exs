defmodule RustQ.Corpus.Control.ForReduce do
  @moduledoc "Fallible for/reduce lowering."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec validate(R.vec(R.u32())) :: R.nif_result(R.unit())
  defrust validate(values) do
    for value <- values, reduce: :ok do
      :ok ->
        if value == 0 do
          {:error, badarg()}
        else
          :ok
        end
    end
  end
end
