defmodule RustQ.NativeCodegen.ModuleHelpers do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec atom(R.path(:Env), R.str()) :: R.nif_result(R.path(:Atom))
  defrust atom(env, name) do
    Atom.from_str(env, name)
  end
end
