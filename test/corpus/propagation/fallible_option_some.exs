defmodule RustQ.Corpus.Propagation.FallibleOptionSome do
  @moduledoc "Propagate fallible values nested inside Some construction."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_rect(term()) :: R.nif_result(R.path(:Rect))
  defrust decode_rect(_term) do
    {:ok, Rect.default()}
  end

  @spec maybe_rect(term()) :: R.nif_result(R.option(R.path(:Rect)))
  defrust maybe_rect(term) do
    {:ok, some(decode_rect(term))}
  end

  @spec use_rect_option(R.option(R.path(:Rect))) :: R.nif_result(R.unit())
  defrust use_rect_option(_rect) do
    :ok
  end

  @spec maybe_rect_from_option(R.option(term())) :: R.nif_result(R.unit())
  defrust maybe_rect_from_option(term) do
    rect =
      case term do
        {:some, term} -> some(decode_rect(term))
        :none -> none()
      end

    use_rect_option(rect)
  end
end
