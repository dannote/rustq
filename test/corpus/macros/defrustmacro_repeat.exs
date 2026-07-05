defmodule RustQ.Corpus.Macros.DefrustmacroRepeat do
  @moduledoc "Expression defrustmacro lowering."

  use RustQ.Meta

  alias RustQ.Type, as: R

  defrustmacro as_u32(term) do
    decode_as!(term, R.u32())
  end

  @spec decode(term()) :: R.nif_result(R.u32())
  defrust decode(term) do
    as_u32!(term)
  end
end
