defmodule RustQ.Corpus.Propagation.MethodChainAutoBorrow do
  @moduledoc "Infer method-chain receiver types and auto-borrow method arguments."

  use RustQ.Meta, rust_sources: ["test/fixtures/method_chain_borrow.rs"]

  alias RustQ.Type, as: R

  @spec run() :: R.path(:SaveLayerRec)
  defrust run() do
    paint = Paint.default()
    SaveLayerRec.default().paint(paint)
  end
end
