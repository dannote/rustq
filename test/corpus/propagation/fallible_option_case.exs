defmodule RustQ.Corpus.Propagation.FallibleOptionCase do
  @moduledoc "Fallible option scrutinees propagate before option-case lowering."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec maybe_size(atom()) :: R.nif_result(R.option(R.f32()))
  defrust maybe_size(_key) do
    {:ok, {:some, 12.0}}
  end

  @spec apply_size(atom()) :: R.nif_result(R.f32())
  defrust apply_size(key) do
    value = 1.0

    case maybe_size(key) do
      {:some, size} -> value = size
      :none -> :ok
    end

    {:ok, value}
  end

  @spec default_size(atom()) :: R.nif_result(R.f32())
  defrust default_size(key) do
    {:ok, maybe_size(key).unwrap_or(1.0)}
  end
end
