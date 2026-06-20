defmodule RustQ.Error do
  @moduledoc """
  Exception raised by bang-style RustQ parsing and rendering APIs.
  """

  defexception [:message, :errors]
end
