defmodule RustQ.NativeCodegen.Helpers do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec atom_key(term(), R.str()) :: R.nif_result(String.t())
  defrust atom_key(term, key) do
    value = unwrap!(term.map_get(unwrap!(atom(term.get_env(), key))))
    value.atom_to_string()
  end

  @spec optional_atom_key(term(), R.str()) :: R.nif_result(R.option(String.t()))
  defrust optional_atom_key(term, key) do
    value = unwrap!(term.map_get(unwrap!(atom(term.get_env(), key))))

    if unwrap!(is_nil(value)) do
      {:ok, nil}
    else
      {:ok, some(unwrap!(value.atom_to_string()))}
    end
  end

  @spec is_nil(term()) :: R.nif_result(boolean())
  defrust is_nil(term) do
    {:ok, term.is_atom() and unwrap!(term.atom_to_string()) == "nil"}
  end

  @spec struct_name(term()) :: R.nif_result(String.t())
  defrust struct_name(term) do
    value = unwrap!(term.map_get(unwrap!(atom(term.get_env(), "__struct__"))))
    value.atom_to_string()
  end

  @spec expect_struct(term(), R.str()) :: R.nif_result(R.unit())
  defrust expect_struct(term, expected) do
    if unwrap!(struct_name(term)) == expected do
      :ok
    else
      {:error, badarg()}
    end
  end

  def asts do
    Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
  end
end
