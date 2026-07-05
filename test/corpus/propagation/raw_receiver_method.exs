defmodule RustQ.Corpus.Propagation.RawReceiverMethod do
  @moduledoc "Raw receiver method calls can infer propagation from Rust source metadata."

  use RustQ.Meta, rust_sources: ["test/fixtures/raw_receiver_methods.rs"]

  alias RustQ.Type, as: R

  @spec read_count(R.mut_ref(R.raw(:"Decoder<'_>"))) :: R.nif_result(R.u32())
  defrust read_count(decoder) do
    count = decoder.read_var_uint()
    {:ok, count}
  end
end
