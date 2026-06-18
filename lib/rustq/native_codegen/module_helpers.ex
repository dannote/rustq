defmodule RustQ.NativeCodegen.ModuleHelpers do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec atom(Env.t(), R.str()) :: R.nif_result(Atom.t())
  defrust atom(env, name) do
    Atom.from_str(env, name)
  end

  def asts do
    Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
  end
end
