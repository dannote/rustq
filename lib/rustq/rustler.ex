defmodule RustQ.Rustler do
  @moduledoc """
  Builders for common Rustler NIF declarations.
  """

  alias RustQ.Rust
  alias RustQ.Rustler.Atoms
  alias RustQ.Rustler.NifStruct
  alias RustQ.Rustler.OptsDecoder
  alias RustQ.Rustler.Resource
  alias RustQ.Rustler.TaggedEnum
  alias RustQ.Rustler.TermDecoder
  alias RustQ.Rustler.TermHelpers

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

  @spec atoms([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          Rust.Fragment.t()
  defdelegate atoms(atoms, opts \\ []), to: Atoms, as: :build

  @spec nif_struct(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  defdelegate nif_struct(name, module, opts \\ []), to: NifStruct, as: :build

  @spec tagged_enum(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate tagged_enum(name, opts), to: TaggedEnum, as: :build

  @spec term_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate term_decoder(name, opts), to: TermDecoder, as: :build

  @spec term_helpers(keyword()) :: [Rust.Fragment.t()]
  defdelegate term_helpers(opts \\ []), to: TermHelpers, as: :build

  @spec resource(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate resource(name, opts \\ []), to: Resource, as: :build

  @spec opts_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate opts_decoder(name, opts), to: OptsDecoder, as: :build

  defp nif_attr(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> "rustler::nif"
      :dirty_cpu -> ~s|rustler::nif(schedule = "DirtyCpu")|
      :dirty_io -> ~s|rustler::nif(schedule = "DirtyIo")|
      value when is_binary(value) -> ~s|rustler::nif(schedule = "#{value}")|
    end
  end
end
