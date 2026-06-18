defmodule RustQ.Rustler.OptsDecoder do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3, function: 3]

  require A
  require I

  @spec field_spec(atom(), RustQ.Meta.Type.t(), keyword()) :: keyword()
  def field_spec(name, %RustQ.Meta.Type{} = type, opts \\ []) do
    required? = Keyword.get(opts, :required, false)
    category = opts_category(type)

    [
      type: opts_field_type(category, type, required?),
      decode: opts_decode(category, name, required?)
    ]
  end

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)

    [
      Rust.item(RustQ.Rust.AST.Render.render_item(struct_ast(name, fields, phantom?, lifetime))),
      Rust.item(
        RustQ.Rust.AST.Render.render_item(
          decoder_ast(name, function_name, fields, phantom?, lifetime, opts_arg)
        )
      )
    ]
  end

  defp struct_ast(name, fields, phantom?, lifetime) do
    I.struct String.to_atom(to_string(name)), vis: :pub, lifetime: lifetime do
      fields(fields, phantom?, lifetime)
    end
  end

  defp decoder_ast(name, function_name, fields, phantom?, lifetime, opts_arg) do
    struct_type = A.type_path(name, lifetimes: List.wrap(lifetime))

    function String.to_atom(to_string(function_name)),
      vis: :pub,
      lifetime: lifetime,
      args: [opts: opts_arg_type(opts_arg)],
      returns: %AST.TypeNifResult{inner: struct_type} do
      A.return(A.ok(A.struct([name], inits(fields, phantom?))))
    end
  end

  defp opts_field_type(:enum, _type, true), do: "Atom"
  defp opts_field_type(:term, _type, true), do: "Term<'a>"
  defp opts_field_type(_category, type, true), do: rust_type(type)
  defp opts_field_type(:enum, _type, false), do: "Option<Atom>"
  defp opts_field_type(:term, _type, false), do: "Option<Term<'a>>"
  defp opts_field_type(_category, type, false), do: "Option<#{rust_type(type)}>"

  defp opts_decode(:number, name, true),
    do: RustQ.Rustler.Decode.opt_decode(:opt_f32, :opts, name)

  defp opts_decode(:boolean, name, true),
    do: RustQ.Rustler.Decode.required_opt_decode(:opt_bool_option, :opts, name)

  defp opts_decode(:atom, name, true),
    do: RustQ.Rustler.Decode.required_opt_decode(:opt_atom_option, :opts, name)

  defp opts_decode(:enum, name, true),
    do: RustQ.Rustler.Decode.required_opt_decode(:opt_atom_option, :opts, name)

  defp opts_decode(:integer, name, true),
    do: RustQ.Rustler.Decode.required_term_decode(:opts, name, :i64)

  defp opts_decode(:string, name, true),
    do: RustQ.Rustler.Decode.required_term_decode(:opts, name, :String)

  defp opts_decode(:term, name, true), do: RustQ.Rustler.Decode.required_term(:opts, name)

  defp opts_decode(:number, name, false),
    do: RustQ.Rustler.Decode.opt_decode(:opt_f32_option, :opts, name)

  defp opts_decode(:boolean, name, false),
    do: RustQ.Rustler.Decode.opt_decode(:opt_bool_option, :opts, name)

  defp opts_decode(:atom, name, false),
    do: RustQ.Rustler.Decode.opt_decode(:opt_atom_option, :opts, name)

  defp opts_decode(:enum, name, false),
    do: RustQ.Rustler.Decode.opt_decode(:opt_atom_option, :opts, name)

  defp opts_decode(:integer, name, false),
    do: RustQ.Rustler.Decode.optional_term_decode(:opts, name, :i64)

  defp opts_decode(:string, name, false),
    do: RustQ.Rustler.Decode.optional_term_decode(:opts, name, :String)

  defp opts_decode(:term, name, false), do: A.call(:opt_term, [:opts, A.atom(name)])

  defp opts_category(%RustQ.Meta.Type{} = type) do
    case RustQ.Meta.Type.category(type) do
      category when category in [:number, :integer, :boolean, :atom, :string, :term, :enum] ->
        category

      _category ->
        :term
    end
  end

  defp rust_type(%RustQ.Meta.Type{ast: ast}) do
    ast
    |> RustQ.Rust.AST.Render.render_type()
    |> IO.iodata_to_binary()
  end

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
