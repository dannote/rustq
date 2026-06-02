defmodule RustQ.Rustler do
  @moduledoc """
  Builders for common Rustler NIF code.

  `RustQ.Rustler` returns `RustQ.Rust` fragments that can be spliced into real
  Rust templates or declared in `rustq.exs` with `rust_items/2`.

  Use the safe helpers by default. Helpers that work with raw
  `rustler::wrapper::NIF_TERM` are named with the `nif_term_` prefix so unsafe
  code stays explicit.
  """

  alias RustQ.Rust

  alias RustQ.Rustler.{
    Atoms,
    CachedAtoms,
    NifStruct,
    NifTermBuilders,
    OptsDecoder,
    Resource,
    Schema,
    TaggedEnum,
    TermBuilders,
    TermDecoder,
    TermHelpers
  }

  @doc """
  Builds a Rustler NIF function declaration.

  Options include `:args`, `:returns`, `:body`, `:vis`, and `:schedule`.
  """
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

  @doc """
  Builds the `rustler::init!` declaration for an Elixir module.
  """
  @spec init(module() | String.t()) :: Rust.Fragment.t()
  def init(module) when is_atom(module), do: init(Atom.to_string(module))
  def init(module) when is_binary(module), do: Rust.item(~s|rustler::init!("#{module}");|)

  @doc """
  Builds a `rustler::atoms!` block.
  """
  @spec atoms([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          Rust.Fragment.t()
  defdelegate atoms(atoms, opts \\ []), to: Atoms, as: :build

  @doc """
  Builds cached atom helper functions backed by `OnceLock<Atom>`.
  """
  @spec cached_atoms([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) :: [
          Rust.Fragment.t()
        ]
  defdelegate cached_atoms(atoms, opts \\ []), to: CachedAtoms, as: :build

  @doc """
  Builds a Rust struct deriving `NifStruct` for an Elixir struct module.
  """
  @spec nif_struct(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  defdelegate nif_struct(name, module, opts \\ []), to: NifStruct, as: :build

  @doc """
  Returns Rust items for a `RustQ.Rustler.Schema` schema.
  """
  @spec schema_items(Schema.t()) :: [Rust.Fragment.t()]
  defdelegate schema_items(schema), to: Schema, as: :rust_items

  @doc """
  Builds a Rust enum that decodes tagged Elixir structs.
  """
  @spec tagged_enum(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate tagged_enum(name, opts), to: TaggedEnum, as: :build

  @doc """
  Builds raw `NIF_TERM` map/struct helpers.

  These helpers generate unsafe Rust and are intended for low-level Rustler code
  where raw terms are required. Prefer `term_builders/1` when `Term<'a>` is
  available.
  """
  @spec nif_term_builders(keyword()) :: [Rust.Fragment.t()]
  defdelegate nif_term_builders(opts \\ []), to: NifTermBuilders, as: :build

  @doc """
  Builds safe `Term<'a>` map/struct helpers.
  """
  @spec term_builders(keyword()) :: [Rust.Fragment.t()]
  defdelegate term_builders(opts \\ []), to: TermBuilders, as: :build

  @doc """
  Builds a decoder function from a Rustler map term into a Rust struct.
  """
  @spec term_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate term_decoder(name, opts), to: TermDecoder, as: :build

  @doc """
  Builds common map/term helper functions used by generated decoders.
  """
  @spec term_helpers(keyword()) :: [Rust.Fragment.t()]
  defdelegate term_helpers(opts \\ []), to: TermHelpers, as: :build

  @doc """
  Builds a Rustler resource struct and resource registration helpers.
  """
  @spec resource(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  defdelegate resource(name, opts \\ []), to: Resource, as: :build

  @doc """
  Returns the `ResourceArc<...>` Rust type for a resource.
  """
  @spec resource_arc(atom() | String.t()) :: String.t()
  defdelegate resource_arc(name), to: Resource, as: :arc

  @doc """
  Builds a decoder function for a Rustler resource.
  """
  @spec resource_decoder(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  defdelegate resource_decoder(name, opts \\ []), to: Resource, as: :decode

  @doc """
  Builds resource initialization code for a Rustler module.
  """
  @spec resource_init(atom() | String.t()) :: Rust.Fragment.t()
  defdelegate resource_init(name), to: Resource, as: :init

  @doc """
  Builds a type alias for a resource's `ResourceArc` type.
  """
  @spec resource_type(atom() | String.t(), keyword()) :: Rust.TypeAlias.t()
  defdelegate resource_type(name, opts \\ []), to: Resource, as: :type_alias

  @doc """
  Builds an options struct plus decoder function for keyword/map options.
  """
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
