defmodule RustQ.Rustler.NifWrappers do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  import RustQ.Rust.AST.ItemBuilder

  require A
  require RustQ.Rust.AST.ItemBuilder

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

    if ast_compatible?(opts) do
      ast =
        function String.to_atom(to_string(name)),
          args: args,
          returns: Keyword.fetch!(opts, :returns),
          lifetime: Keyword.get(opts, :lifetime),
          vis: Keyword.get(opts, :vis),
          attrs: [nif_attribute(opts)] do
          A.return(A.call(String.to_atom(to_string(impl)), Keyword.keys(args)))
        end

      Rust.item(AST.render_item_native(ast))
    else
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
  end

  defp ast_compatible?(opts) do
    impl = Keyword.get(opts, :impl)

    Keyword.has_key?(opts, :returns) and Keyword.get(opts, :lifetimes, []) == [] and
      Keyword.get(opts, :generics, []) == [] and Keyword.get(opts, :where, []) == [] and
      (is_nil(impl) or simple_ident?(impl))
  end

  defp simple_ident?(value) do
    value
    |> to_string()
    |> String.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/)
  end

  defp nif_attribute(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> A.nif_attr()
      :dirty_cpu -> A.nif_attr(schedule: "DirtyCpu")
      :dirty_io -> A.nif_attr(schedule: "DirtyIo")
      value when is_binary(value) -> A.nif_attr(schedule: value)
    end
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
