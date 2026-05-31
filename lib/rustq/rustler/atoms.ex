defmodule RustQ.Rustler.Atoms do
  @moduledoc false

  alias RustQ.Rust

  @spec build([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          Rust.Fragment.t()
  def build(atoms, opts \\ []) do
    body =
      atoms
      |> Enum.map(&atom_decl/1)
      |> Enum.map_join("\n", fn decl -> "        #{decl}" end)

    module = Keyword.get(opts, :module, :atoms)
    code = ["rustler::atoms! {\n", body, "\n}"]

    case module do
      false -> Rust.item(code)
      module -> Rust.item(["mod ", to_string(module), " {\n", indent(code, 4), "\n}"])
    end
  end

  defp indent(iodata, spaces) do
    padding = String.duplicate(" ", spaces)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> padding <> line
    end)
  end

  defp atom_decl(name) when is_atom(name), do: "#{name},"
  defp atom_decl(name) when is_binary(name), do: "#{name},"

  defp atom_decl({name, value}) when (is_atom(name) or is_binary(name)) and is_binary(value),
    do: ~s|#{name} = "#{value}",|
end
