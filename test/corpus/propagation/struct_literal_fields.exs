defmodule RustQ.Corpus.Propagation.StructLiteralFields do
  @moduledoc "Struct literal fields are checked against expected field types."

  use RustQ.Meta

  alias RustQ.Type, as: R

  defmodule Point do
    defstruct [:x, :y]
  end

  @type point :: %Point{x: R.f32(), y: R.f32()}

  @spec decode_x(term()) :: R.nif_result(R.f32())
  defrust decode_x(term) do
    decode_as!(term, R.f32())
  end

  @spec consume(point()) :: R.nif_result(R.unit())
  defrust consume(_point) do
    :ok
  end

  @spec run(term()) :: R.nif_result(R.unit())
  defrust run(term) do
    point = struct_literal(Point, x: decode_x(term), y: 0.0)
    consume(point)
    :ok
  end
end
