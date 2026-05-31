defmodule RustQ.Native do
  @moduledoc false

  use Rustler, otp_app: :rustq, crate: "rustq_nif"

  def parse(_source), do: :erlang.nif_error(:nif_not_loaded)
  def render(_source, _bindings, _splices), do: :erlang.nif_error(:nif_not_loaded)
end
