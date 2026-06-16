defmodule RustQ.NativeCodegen.Decoders do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_pat_wildcard(term()) :: R.nif_result(R.pat())
  defrust decode_pat_wildcard(_term) do
    Super.parse_pat(token_macro(:quote, "_"))
  end

  @spec decode_pat_none(term()) :: R.nif_result(R.pat())
  defrust decode_pat_none(_term) do
    Super.parse_pat(token_macro(:quote, "None"))
  end

  @spec decode_expr_none(term()) :: R.nif_result(R.expr())
  defrust decode_expr_none(_term) do
    Super.parse_expr("None")
  end

  def asts do
    Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
  end
end
