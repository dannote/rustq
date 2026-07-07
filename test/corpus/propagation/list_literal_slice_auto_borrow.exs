defmodule RustQ.Corpus.Propagation.ListLiteralSliceAutoBorrow do
  @moduledoc "Auto-borrow list literals passed where slice arguments are expected."

  use RustQ.Meta, rust_sources: ["test/fixtures/slice_list_literal.rs"]

  alias RustQ.Type, as: R

  @spec run(R.mut_ref(R.path(:TextStyle)), R.path(:String)) :: R.nif_result(R.unit())
  defrust run(style, family) do
    style.set_font_families([family])
    :ok
  end

  @spec use_str(R.str()) :: R.nif_result(R.unit())
  defrust use_str(_value) do
    :ok
  end

  @spec string_to_str(R.path(:String)) :: R.nif_result(R.unit())
  defrust string_to_str(value) do
    use_str(value)
    :ok
  end

  @spec use_values(R.slice(R.u32())) :: R.nif_result(R.unit())
  defrust use_values(_values) do
    :ok
  end

  @spec loop_values(R.vec({R.path(:String), R.vec(R.u32())})) :: R.nif_result(R.unit())
  defrust loop_values(spans) do
    for {_name, values} <- spans do
      use_values(values)
    end

    :ok
  end
end
