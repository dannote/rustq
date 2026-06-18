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
    AtomDecoder,
    AtomDispatch,
    Atoms,
    CachedAtoms,
    NifStruct,
    NifTermBuilders,
    NifWrappers,
    OptsDecoder,
    OptsHelpers,
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
    |> Rust.attr(NifWrappers.nif_attr(opts))
  end

  @doc """
  Builds exported Rustler NIF functions that delegate to implementation functions.

  This is useful when the exported Rustler surface is repetitive but the
  implementation bodies should stay handwritten.

      RustQ.Rustler.nif_exports([
        render_png: [
          args: [env: "Env<'a>", batch: "Term<'a>"],
          returns: "NifResult<Term<'a>>",
          lifetime: :a,
          schedule: :dirty_cpu
        ]
      ])

  Generates a `#[rustler::nif] fn render_png(...) { render_png_impl(...) }`
  export. Pass `:impl` to override the implementation function name.
  """
  @spec nif_exports([{atom() | String.t(), keyword()}]) :: [Rust.Function.t()]
  def nif_exports(specs), do: NifWrappers.build(specs)

  @doc """
  Builds a single exported Rustler NIF function.
  """
  @spec nif_export(atom() | String.t(), keyword()) :: Rust.Function.t()
  def nif_export(name, opts), do: NifWrappers.build(name, opts)

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
  def atoms(atoms, opts \\ []), do: Atoms.build(atoms, opts)

  @doc """
  Builds a decoder from Rustler atoms into a Rust enum/value type.

      RustQ.Rustler.atom_decoder(:decode_blend_mode,
        returns: :BlendMode,
        cases: [src_over: "BlendMode::SrcOver", multiply: "BlendMode::Multiply"]
      )

  The generated function returns `NifResult<returns>` by default. Pass `:result`
  to override the full return type, `:input` to override the input type, `:atoms`
  to override the atoms module, and `:unknown` to override the fallback branch.
  """
  @spec atom_decoder(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def atom_decoder(name, opts), do: AtomDecoder.build(name, opts)

  @doc """
  Builds a function that dispatches on an atom expression.

      RustQ.Rustler.atom_dispatch(:draw_command,
        args: [surface: "&mut Surface", command: "Term<'a>"],
        on: "command.map_get(atoms::op())?.decode::<Atom>()?",
        cases: [rect: "draw_rect(surface, command)"],
        unknown: "Ok(())"
      )

  This is intentionally generic: use it for command dispatch, tagged map
  dispatch, AST node dispatch, or any other Rustler atom switch.
  """
  @spec atom_dispatch(atom() | String.t(), keyword()) :: Rust.Function.t()
  def atom_dispatch(name, opts), do: AtomDispatch.build(name, opts)

  @doc """
  Builds keyword/options helper functions over `&[(Atom, Term<'a>)]`.

  By default this includes `decode_opts`, `decode_args`, `opt_term`,
  `opt_f32`, `opt_f32_option`, `opt_f32_default`, `opt_bool_option`, and
  `opt_atom_option`. Pass `:include` or `:exclude` to select helpers.

      RustQ.Rustler.opts_helpers(include: [:decode_opts, :decode_args, :opt_term])

  `decode_opts` extracts from `atoms::opts()` by default. Pass `:key` to use a
  different map key expression. `decode_args` extracts from `atoms::args()` by
  default; pass `:args_key` to use a different map key expression.
  """
  @spec opts_helpers(keyword()) :: [Rust.Fragment.t()]
  def opts_helpers(opts \\ []), do: OptsHelpers.build(opts)

  @doc """
  Builds cached atom helper functions backed by `OnceLock<Atom>`.
  """
  @spec cached_atoms([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) :: [
          Rust.Fragment.t()
        ]
  def cached_atoms(atoms, opts \\ []), do: CachedAtoms.build(atoms, opts)

  @doc """
  Builds a Rust struct deriving `NifStruct` for an Elixir struct module.
  """
  @spec nif_struct(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  def nif_struct(name, module, opts \\ []), do: NifStruct.build(name, module, opts)

  @doc """
  Returns Rust items for a `RustQ.Rustler.Schema` schema.
  """
  @spec schema_items(Schema.t()) :: [Rust.Fragment.t()]
  def schema_items(schema), do: Schema.rust_items(schema)

  @doc """
  Builds a Rust enum that decodes tagged Elixir structs.
  """
  @spec tagged_enum(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def tagged_enum(name, opts), do: TaggedEnum.build(name, opts)

  @doc """
  Builds raw `NIF_TERM` map/struct helpers.

  These helpers generate unsafe Rust and are intended for low-level Rustler code
  where raw terms are required. Prefer `term_builders/1` when `Term<'a>` is
  available.
  """
  @spec nif_term_builders(keyword()) :: [Rust.Fragment.t()]
  def nif_term_builders(opts \\ []), do: NifTermBuilders.build(opts)

  @doc """
  Builds safe `Term<'a>` map/struct helpers.
  """
  @spec term_builders(keyword()) :: [Rust.Fragment.t()]
  def term_builders(opts \\ []), do: TermBuilders.build(opts)

  @doc """
  Builds a decoder function from a Rustler map term into a Rust struct.
  """
  @spec term_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def term_decoder(name, opts), do: TermDecoder.build(name, opts)

  @doc """
  Builds common map/term helper functions used by generated decoders.
  """
  @spec term_helpers(keyword()) :: [Rust.Fragment.t()]
  def term_helpers(opts \\ []), do: TermHelpers.build(opts)

  @doc """
  Builds a Rustler resource struct and resource registration helpers.
  """
  @spec resource(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def resource(name, opts \\ []), do: Resource.build(name, opts)

  @doc """
  Builds a Rustler resource plus an Elixir handle decoder.

  The generated decoder extracts a `ResourceArc<...>` from a field on an
  Elixir-facing handle struct or map. The field defaults to `"ref"`.

      RustQ.Rustler.resource_handle(:EncodedImage,
        fields: [bytes: "Vec<u8>"],
        handle_field: "ref"
      )

  Pass `:decoder` to override the decoder function name.
  """
  @spec resource_handle(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def resource_handle(name, opts \\ []), do: Resource.handle(name, opts)

  @doc """
  Returns the `ResourceArc<...>` Rust type for a resource.
  """
  @spec resource_arc(atom() | String.t()) :: String.t()
  def resource_arc(name), do: Resource.arc(name)

  @doc """
  Builds a decoder function for a Rustler resource.
  """
  @spec resource_decoder(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def resource_decoder(name, opts \\ []), do: Resource.decode(name, opts)

  @doc """
  Builds resource initialization code for a Rustler module.
  """
  @spec resource_init(atom() | String.t()) :: Rust.Fragment.t()
  def resource_init(name), do: Resource.init(name)

  @doc """
  Builds a type alias for a resource's `ResourceArc` type.
  """
  @spec resource_type(atom() | String.t(), keyword()) :: Rust.TypeAlias.t()
  def resource_type(name, opts \\ []), do: Resource.type_alias(name, opts)

  @doc """
  Builds an options struct plus decoder function for keyword/options.

  Field specs may be explicit Rust boundary specs:

      RustQ.Rustler.opts_decoder(:RectOpts,
        fields: [x: [type: :f32, decode: RustQ.Rustler.Decode.opt_decode(:opt_f32, :opts, :x)]]
      )

  Or structural RustQ types, where the builder derives the Rust boundary type
  and decoder from `RustQ.Meta.Type.category/1`:

      RustQ.Rustler.opts_decoder(:RectOpts,
        fields: [x: [type: RustQ.Spec.type(quote(do: RustQ.Type.f32())), required: true]]
      )

  Structural external/domain types remain `Term<'a>` at the boundary unless an
  explicit `:decode` expression is supplied.
  """
  @spec opts_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def opts_decoder(name, opts), do: OptsDecoder.build(name, opts)
end
