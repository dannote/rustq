defmodule RustQ.Corpus.Propagation.ReturnStructLiteralFields do
  @moduledoc "Ok-returned struct literal fields are checked against result inner field types."

  use RustQ.Meta

  alias RustQ.Type, as: R

  defmodule Point do
    defstruct [:x, :y]
  end

  @type point :: %Point{x: R.f64(), y: R.f64()}

  @spec decode_float(term()) :: R.nif_result(R.f64())
  defrust decode_float(term) do
    decode_as!(term, R.f64())
  end

  @spec run(term()) :: R.nif_result(point())
  defrust run(term) do
    {:ok,
     struct_literal(Point,
       x: decode_float(term),
       y: cast(decode_float(term), R.f64())
     )}
  end
end
