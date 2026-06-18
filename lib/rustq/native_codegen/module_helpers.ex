defmodule RustQ.NativeCodegen.ModuleHelpers do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec atom(Env.t(), R.str()) :: R.nif_result(Atom.t())
  defrust atom(env, name) do
    Atom.from_str(env, name)
  end
end
