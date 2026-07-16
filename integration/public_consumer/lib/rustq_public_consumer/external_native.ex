defmodule RustQPublicConsumer.ExternalNative do
  @moduledoc false

  use RustQ.Native,
    build: false,
    load: false,
    crate: :rustq_public_consumer_external

  alias RustQ.Type, as: R

  @type result :: %{required(:value) => integer()}

  @spec wrap(term()) :: R.nif_result(term())
  defnif(wrap(value), do: wrap_impl(nif_env(), value))
end
