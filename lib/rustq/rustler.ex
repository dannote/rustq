defmodule RustQ.Rustler do
  @moduledoc """
  Builders for common Rustler NIF declarations.
  """

  alias RustQ.Rust

  @spec nif(atom() | String.t(), keyword()) :: Rust.Function.t()
  def nif(name, opts \\ []) do
    name
    |> Rust.fn(
      args: Keyword.get(opts, :args, []),
      returns: Keyword.get(opts, :returns),
      body: Keyword.get(opts, :body, ""),
      vis: Keyword.get(opts, :vis)
    )
    |> Rust.attr(nif_attr(opts))
  end

  @spec init(module() | String.t()) :: Rust.Fragment.t()
  def init(module) when is_atom(module), do: init(Atom.to_string(module))
  def init(module) when is_binary(module), do: Rust.item(~s|rustler::init!("#{module}");|)

  @spec atoms([atom() | String.t() | {atom() | String.t(), String.t()}]) :: Rust.Fragment.t()
  def atoms(atoms) do
    body =
      atoms
      |> Enum.map(&atom_decl/1)
      |> Enum.map_join("\n", fn decl -> "        #{decl}" end)

    Rust.item("""
    mod atoms {
        rustler::atoms! {
    #{body}
        }
    }
    """)
  end

  defp nif_attr(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> "rustler::nif"
      :dirty_cpu -> ~s|rustler::nif(schedule = "DirtyCpu")|
      :dirty_io -> ~s|rustler::nif(schedule = "DirtyIo")|
      value when is_binary(value) -> ~s|rustler::nif(schedule = "#{value}")|
    end
  end

  defp atom_decl(name) when is_atom(name), do: "#{name},"
  defp atom_decl(name) when is_binary(name), do: "#{name},"

  defp atom_decl({name, value}) when (is_atom(name) or is_binary(name)) and is_binary(value),
    do: ~s|#{name} = "#{value}",|
end
