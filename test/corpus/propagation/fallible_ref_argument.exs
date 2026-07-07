defmodule RustQ.Corpus.Propagation.FallibleRefArgument do
  @moduledoc "Propagate fallible values and borrow them for reference arguments."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode(term()) :: R.nif_result(R.path(:Matrix))
  defrust decode(_term) do
    {:ok, Matrix.default()}
  end

  @spec consume(R.ref(R.path(:Matrix))) :: R.nif_result(R.unit())
  defrust consume(_matrix) do
    :ok
  end

  @spec run(term()) :: R.nif_result(R.unit())
  defrust run(term) do
    consume(decode(term))
  end
end
