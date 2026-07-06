defmodule RustQ.Corpus.Propagation.StaticAutoBorrow do
  @moduledoc "External static metadata supports expected-reference auto-borrow."

  use RustQ.Meta, rust_sources: ["test/fixtures/external_statics.rs"]

  alias RustQ.Type, as: R

  @spec cached_atom(R.ref(R.raw(:"OnceLock<Atom>"))) :: R.nif_result(R.unit())
  defrust(cached_atom(_cell), do: :ok)

  @spec run() :: R.nif_result(R.unit())
  defrust run() do
    cached_atom(GUID_ATOM)
    :ok
  end
end
