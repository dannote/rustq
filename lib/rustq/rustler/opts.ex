defmodule RustQ.Rustler.Opts do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Meta.Type
  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I
  alias RustQ.Rustler.Decode
  alias RustQ.Rustler.HelperSelection
  alias RustQ.Type, as: R

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3, function: 3]

  require A
  require I

  @helper_names [
    :decode_opts,
    :decode_args,
    :opt_term,
    :opt_f32,
    :opt_f32_option,
    :opt_f32_default,
    :opt_bool_option,
    :opt_atom_option
  ]

  @rusty_names @helper_names

  defrustmod(Rustler, as: :rustler)

  @spec decode_opts(term()) :: R.nif_result(R.vec({R.path(:Atom), term()}))
  defrust decode_opts(term) do
    decode_as(unwrap!(term.map_get(Atoms.opts())), R.vec({R.path(:Atom), term()}))
  end

  @spec decode_args(term()) :: R.nif_result(R.vec(term()))
  defrust decode_args(term) do
    decode_as(unwrap!(term.map_get(Atoms.args())), R.vec(term()))
  end

  @spec opt_term(R.slice({R.path(:Atom), term()}), R.path(:Atom)) :: R.option(term())
  defrust opt_term(opts, key) do
    for {atom, term} <- opts.iter() do
      if deref(atom) == key do
        return!(deref(term))
      end
    end

    nil
  end

  @spec opt_f32(R.slice({R.path(:Atom), term()}), R.path(:Atom)) :: R.nif_result(R.f32())
  defrust opt_f32(opts, key) do
    case opt_term(opts, key) do
      {:some, term} ->
        value = cast(decode_as!(term, R.f64()), :f32)

        if value.is_nan() do
          {:error, Rustler.Error.BadArg}
        else
          {:ok, value}
        end

      :none ->
        {:error, Rustler.Error.BadArg}
    end
  end

  @spec opt_f32_option(R.slice({R.path(:Atom), term()}), R.path(:Atom)) ::
          R.nif_result(R.option(R.f32()))
  defrust opt_f32_option(opts, key) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, some(cast(decode_as!(term, R.f64()), :f32))}
      :none -> {:ok, nil}
    end
  end

  @spec opt_f32_default(R.slice({R.path(:Atom), term()}), R.path(:Atom), R.f32()) ::
          R.nif_result(R.f32())
  defrust opt_f32_default(opts, key, default) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, cast(decode_as!(term, R.f64()), :f32)}
      :none -> {:ok, default}
    end
  end

  @spec opt_bool_option(R.slice({R.path(:Atom), term()}), R.path(:Atom)) ::
          R.nif_result(R.option(boolean()))
  defrust opt_bool_option(opts, key) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, some(decode_as!(term, R.bool()))}
      :none -> {:ok, nil}
    end
  end

  @spec opt_atom_option(R.slice({R.path(:Atom), term()}), R.path(:Atom)) ::
          R.nif_result(R.option(R.path(:Atom)))
  defrust opt_atom_option(opts, key) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, some(decode_as!(term, R.path(:Atom)))}
      :none -> {:ok, nil}
    end
  end

  @spec helpers(keyword()) :: [Rust.Fragment.t()]
  def helpers(opts \\ []) do
    opts
    |> helper_names()
    |> Enum.map(&helper_item/1)
  end

  @spec decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def decoder(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = opts |> Keyword.fetch!(:fields) |> normalize_fields()
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)

    Rust.ast_items([
      struct_ast(name, fields, phantom?, lifetime),
      decoder_ast(name, function_name, fields, phantom?, lifetime, opts_arg)
    ])
  end

  defp helper_item(name) when name in @rusty_names, do: RustQ.Meta.item(__MODULE__, name)

  defp helper_names(opts), do: HelperSelection.names(opts, @helper_names)

  defp struct_ast(name, fields, phantom?, lifetime) do
    I.struct RustQ.Atom.identifier!(to_string(name)), vis: :pub, lifetime: lifetime do
      fields(fields, phantom?, lifetime)
    end
  end

  defp decoder_ast(name, function_name, fields, phantom?, lifetime, opts_arg) do
    struct_type = A.type_path(name, lifetimes: List.wrap(lifetime))

    function RustQ.Atom.identifier!(to_string(function_name)),
      vis: :pub,
      lifetime: lifetime,
      args: [opts: opts_arg_type(opts_arg)],
      returns: %AST.TypeNifResult{inner: struct_type} do
      A.return(A.ok(A.struct([name], inits(fields, phantom?))))
    end
  end

  defp normalize_fields(fields),
    do: Enum.map(fields, fn {name, spec} -> {name, normalize_field(name, spec)} end)

  defp normalize_field(name, spec) do
    type = Keyword.fetch!(spec, :type)

    if match?(%Type{}, type) and not Keyword.has_key?(spec, :decode) do
      required? = Keyword.get(spec, :required, false)
      [type: boundary_type(type, required?), decode: boundary_decode(type, name, required?)]
    else
      spec
    end
  end

  defp boundary_type(%Type{} = type, true), do: boundary_inner_type(type)

  defp boundary_type(%Type{} = type, false),
    do: %AST.TypeOption{inner: boundary_inner_type(type)}

  defp boundary_inner_type(%Type{} = type) do
    case Type.category(type) do
      category when category in [:atom, :enum] -> A.type_path(:Atom)
      category when category in [:number, :integer, :boolean, :string] -> type.ast
      _category -> A.type_path(:Term, lifetimes: [:a])
    end
  end

  defp boundary_decode(%Type{kind: :f32}, name, true),
    do: Decode.opt_decode(:opt_f32, :opts, name)

  defp boundary_decode(%Type{kind: :f32}, name, false),
    do: Decode.opt_decode(:opt_f32_option, :opts, name)

  defp boundary_decode(%Type{} = type, name, required?) do
    case Type.category(type) do
      :boolean ->
        helper_decode(:opt_bool_option, name, required?)

      category when category in [:atom, :enum] ->
        helper_decode(:opt_atom_option, name, required?)

      :term when required? ->
        Decode.required_term(:opts, name)

      :term ->
        A.call(:opt_term, [:opts, A.atom(name)])

      category when category in [:number, :integer, :string] ->
        term_decode(type.ast, name, required?)

      _category when required? ->
        Decode.required_term(:opts, name)

      _category ->
        A.call(:opt_term, [:opts, A.atom(name)])
    end
  end

  defp helper_decode(helper, name, true),
    do: Decode.required_opt_decode(helper, :opts, name)

  defp helper_decode(helper, name, false),
    do: Decode.opt_decode(helper, :opts, name)

  defp term_decode(type, name, true),
    do: Decode.required_term_decode(:opts, name, type)

  defp term_decode(type, name, false),
    do: Decode.optional_term_decode(:opts, name, type)

  defp opts_arg_type("opts: " <> type), do: type
  defp opts_arg_type(type), do: type

  defp fields(fields, phantom?, lifetime) do
    fields =
      Enum.map(fields, fn {field_name, spec} ->
        field(field_name, Keyword.fetch!(spec, :type), vis: :pub)
      end)

    if phantom? do
      fields ++ [field(:_phantom, {:raw, phantom_type(lifetime)}, [])]
    else
      fields
    end
  end

  defp inits(fields, phantom?) do
    field_inits =
      Enum.map(fields, fn {field_name, spec} ->
        {field_name, decode_expression(Keyword.fetch!(spec, :decode))}
      end)

    if phantom? do
      field_inits ++ [phantom_init()]
    else
      field_inits
    end
  end

  defp decode_expression(%{__struct__: _} = ast), do: A.expr(ast)
  defp decode_expression(source) when is_binary(source), do: A.escape_expr(source)

  defp phantom_init, do: {:_phantom, A.path_value([:std, :marker, :PhantomData])}

  defp phantom_type(nil), do: "std::marker::PhantomData<()>"
  defp phantom_type(lifetime), do: "std::marker::PhantomData<&'#{lifetime} ()>"

  defp default_decoder_name(name), do: "decode_#{Macro.underscore(to_string(name))}"
  defp lifetime_generics(nil), do: ""
  defp lifetime_generics(lifetime), do: "<'#{lifetime}>"
end
