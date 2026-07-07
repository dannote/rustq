defmodule RustQ.Corpus.Propagation.FallibleRefAccess do
  @moduledoc "Propagate fallible references through deref and decode_as."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec use_term(term()) :: R.nif_result(R.unit())
  defrust use_term(_term) do
    :ok
  end

  @spec decode_first(R.vec(term())) :: R.nif_result(R.path(:String))
  defrust decode_first(args) do
    text = decode_as!(args.first().ok_or(badarg()), R.path(:String))
    {:ok, text}
  end

  @spec deref_first(R.vec(term())) :: R.nif_result(R.unit())
  defrust deref_first(args) do
    term = deref(args.first().ok_or(badarg()))
    use_term(term)
  end

  @spec decode_map_field(term()) :: R.nif_result(R.path(:String))
  defrust decode_map_field(term) do
    value = decode_as!(term.map_get(Atoms.value()), R.path(:String))
    {:ok, value}
  end
end
