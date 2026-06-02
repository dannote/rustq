defmodule RustQ.Rustler do
  @moduledoc """
  Builders for common Rustler NIF declarations.
  """

  alias RustQ.Rust

  alias RustQ.Rustler.{
    Atoms,
    CachedAtoms,
    NifStruct,
    OptsDecoder,
    Resource,
    Schema,
    TaggedEnum,
    TermBuilders,
    TermDecoder,
    TermHelpers
  }

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

  @spec cached_atom_fns([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) :: [
          Rust.Fragment.t()
        ]
  defdelegate cached_atom_fns(atoms, opts \\ []), to: CachedAtoms, as: :build

  @spec nif_struct(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  defdelegate nif_struct(name, module, opts \\ []), to: NifStruct, as: :build

  @spec schema_items(Schema.t()) :: [Rust.Fragment.t()]
  defdelegate schema_items(schema), to: Schema, as: :rust_items

  @spec tagged_enum(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate tagged_enum(name, opts), to: TaggedEnum, as: :build

  @spec term_builders(keyword()) :: [Rust.Fragment.t()]
  defdelegate term_builders(opts \\ []), to: TermBuilders, as: :build

  @spec term_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate term_decoder(name, opts), to: TermDecoder, as: :build

  @spec term_helpers(keyword()) :: [Rust.Fragment.t()]
  defdelegate term_helpers(opts \\ []), to: TermHelpers, as: :build

  @spec resource(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate resource(name, opts \\ []), to: Resource, as: :build

  @spec resource_arc(atom() | String.t()) :: String.t()
  defdelegate resource_arc(name), to: Resource, as: :arc

  @spec resource_decode(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  defdelegate resource_decode(name, opts \\ []), to: Resource, as: :decode

  @spec resource_init(atom() | String.t()) :: Rust.Fragment.t()
  defdelegate resource_init(name), to: Resource, as: :init

  @spec resource_type(atom() | String.t(), keyword()) :: Rust.TypeAlias.t()
  defdelegate resource_type(name, opts \\ []), to: Resource, as: :type_alias

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
