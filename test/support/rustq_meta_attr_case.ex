defmodule RustQ.Meta.AttrCase do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @allow :dead_code
  @allow Clippy.redundant_field_names()
  @nif schedule: "DirtyCpu"
  @spec render(term()) :: R.nif_result(term())
  defrust render(term) do
    render_impl(term)
  end
end
