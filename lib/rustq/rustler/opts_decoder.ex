defmodule RustQ.Rustler.OptsDecoder do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3, function: 3]

  require A
  require I

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = opts |> Keyword.fetch!(:fields) |> normalize_fields()
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

  defp normalize_fields(fields),
    do: Enum.map(fields, fn {name, spec} -> {name, normalize_field(name, spec)} end)

  defp normalize_field(name, spec) do
    type = Keyword.fetch!(spec, :type)

    if match?(%RustQ.Meta.Type{}, type) and not Keyword.has_key?(spec, :decode) do
      required? = Keyword.get(spec, :required, false)
      [type: boundary_type(type, required?), decode: boundary_decode(type, name, required?)]
    else
      spec
    end
  end

  defp boundary_type(%RustQ.Meta.Type{} = type, true), do: boundary_inner_type(type)

  defp boundary_type(%RustQ.Meta.Type{} = type, false),
    do: %AST.TypeOption{inner: boundary_inner_type(type)}

  defp boundary_inner_type(%RustQ.Meta.Type{} = type) do
    case RustQ.Meta.Type.category(type) do
      category when category in [:atom, :enum] -> A.type_path(:Atom)
      category when category in [:number, :integer, :boolean, :string] -> type.ast
      _category -> A.type_path(:Term, lifetimes: [:a])
    end
  end

  defp boundary_decode(%RustQ.Meta.Type{kind: :f32}, name, true),
    do: RustQ.Rustler.Decode.opt_decode(:opt_f32, :opts, name)

  defp boundary_decode(%RustQ.Meta.Type{kind: :f32}, name, false),
    do: RustQ.Rustler.Decode.opt_decode(:opt_f32_option, :opts, name)

  defp boundary_decode(%RustQ.Meta.Type{} = type, name, required?) do
    case RustQ.Meta.Type.category(type) do
      :boolean ->
        helper_decode(:opt_bool_option, name, required?)

      category when category in [:atom, :enum] ->
        helper_decode(:opt_atom_option, name, required?)

      :term when required? ->
        RustQ.Rustler.Decode.required_term(:opts, name)

      :term ->
        A.call(:opt_term, [:opts, A.atom(name)])

      category when category in [:number, :integer, :string] ->
        term_decode(type.ast, name, required?)

      _category when required? ->
        RustQ.Rustler.Decode.required_term(:opts, name)

      _category ->
        A.call(:opt_term, [:opts, A.atom(name)])
    end
  end

  defp helper_decode(helper, name, true),
    do: RustQ.Rustler.Decode.required_opt_decode(helper, :opts, name)

  defp helper_decode(helper, name, false),
    do: RustQ.Rustler.Decode.opt_decode(helper, :opts, name)

  defp term_decode(type, name, true),
    do: RustQ.Rustler.Decode.required_term_decode(:opts, name, type)

  defp term_decode(type, name, false),
    do: RustQ.Rustler.Decode.optional_term_decode(:opts, name, type)

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
