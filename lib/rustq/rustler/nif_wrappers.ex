defmodule RustQ.Rustler.NifWrappers do
  @moduledoc false

  alias RustQ.Rust

  @type spec :: {atom() | String.t(), keyword()}

  @spec build([spec()]) :: [Rust.Function.t()]
  def build(specs) do
    Enum.map(specs, fn {name, opts} -> wrapper(name, opts) end)
  end

  @spec build(atom() | String.t(), keyword()) :: Rust.Function.t()
  def build(name, opts), do: wrapper(name, opts)

  defp wrapper(name, opts) do
    args = Keyword.get(opts, :args, [])
    impl = Keyword.get(opts, :impl, "#{name}_impl")
    call_args = args |> Keyword.keys() |> Enum.map_join(", ", &to_string/1)

    name
    |> Rust.fn(
      args: args,
      returns: Keyword.get(opts, :returns),
      lifetime: Keyword.get(opts, :lifetime),
      lifetimes: Keyword.get(opts, :lifetimes, []),
      generics: Keyword.get(opts, :generics, []),
      where: Keyword.get(opts, :where, []),
      body: "#{impl}(#{call_args})",
      vis: Keyword.get(opts, :vis)
    )
    |> Rust.attr(nif_attr(opts))
  end

  @doc false
  @spec nif_attr(keyword()) :: String.t()
  def nif_attr(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> "rustler::nif"
      :dirty_cpu -> ~s|rustler::nif(schedule = "DirtyCpu")|
      :dirty_io -> ~s|rustler::nif(schedule = "DirtyIo")|
      value when is_binary(value) -> ~s|rustler::nif(schedule = "#{value}")|
    end
  end
end
