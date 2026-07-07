defmodule RustQ.Corpus.Propagation.OptionOkOrDownstream do
  @moduledoc "Infer propagation for option ok_or results from downstream reference use."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec maybe_path() :: R.option(R.path(:Path))
  defrust maybe_path() do
    Path.default()
  end

  @spec use_path(R.mut_ref(R.path(:Path))) :: R.nif_result(R.unit())
  defrust use_path(_path) do
    :ok
  end

  @spec run() :: R.nif_result(R.unit())
  defrust run() do
    path = maybe_path().ok_or(badarg())
    use_path(path)
  end
end
