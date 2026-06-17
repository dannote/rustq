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
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)

    [
      Rust.item(
        RustQ.Rust.AST.Render.render_item_native(struct_ast(name, fields, phantom?, lifetime))
      ),
      Rust.item(
        RustQ.Rust.AST.Render.render_item_native(
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
