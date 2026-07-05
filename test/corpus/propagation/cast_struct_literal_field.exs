defmodule RustQ.Corpus.Propagation.CastStructLiteralField do
  @moduledoc "Struct literal field checking propagates through cast/2 operands."

  use RustQ.Meta

  alias RustQ.Type, as: R

  defmodule Point do
    defstruct [:x]
  end

  @type point :: %Point{x: R.f32()}

  @spec decode_i64(term()) :: R.nif_result(R.i64())
  defrust decode_i64(term) do
    decode_as!(term, R.i64())
  end

  @spec consume(point()) :: R.nif_result(R.unit())
  defrust consume(_point) do
    :ok
  end

  @spec run(term()) :: R.nif_result(R.unit())
  defrust run(term) do
    point = struct_literal(Point, x: cast(decode_i64(term), R.f32()))
    consume(point)
    :ok
  end
end
