defmodule RustQ.Corpus.Propagation.SliceFieldAutoBorrow do
  @moduledoc "Auto-borrow a struct field reached through slice get and unwrap."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @type kind :: R.enum(one: [], repeated: [])
  @type field :: %{required(:kind) => kind()}

  @spec use_kind(R.ref(kind())) :: R.nif_result(R.unit())
  defrust(use_kind(_kind), do: :ok)

  @spec run(R.slice(field()), R.usize()) :: R.nif_result(R.unit())
  defrust run(fields, index) do
    field = fields.get(index).unwrap()
    use_kind(field.kind)
    :ok
  end
end
