defmodule RustQ.Rustler.TermDecoder do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  require I

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    lifetime = Keyword.get(opts, :lifetime, :a)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    term_arg = Keyword.get(opts, :term_arg, :term)
    term_type = Keyword.get(opts, :term_type, "Term<'#{lifetime}>")

    result = Keyword.get(opts, :result, :nif)
    result_type = result_type(name, lifetime, result)

    Rust.ast_items([
      struct_ast(name, fields, lifetime),
      decoder_ast(name, function_name, fields, term_arg, term_type, result_type, result, lifetime)
    ])
  end

  defp struct_ast(name, fields, lifetime) do
    I.struct ident_atom(name), lifetime: lifetime do
      struct_fields(fields)
    end
  end

  defp decoder_ast(
         name,
         function_name,
         fields,
         term_arg,
         term_type,
         result_type,
         result,
         lifetime
       ) do
    %AST.Function{
      name: ident_atom(function_name),
      lifetime: lifetime,
      args: [A.arg(ident_atom(term_arg), term_type)],
      returns: Rust.type(result_type),
      body: [
        A.return_stmt(
          A.ok(A.struct(A.path(ident_atom(name)), decoder_inits(fields, term_arg, result)))
        )
      ]
    }
  end

  defp struct_fields(fields) do
    Enum.map(fields, fn {field_name, spec} ->
      I.field(field_name, Keyword.fetch!(spec, :type), vis: nil)
    end)
  end

  defp decoder_inits(fields, term_arg, result) do
    Enum.map(fields, fn {field_name, spec} ->
      spec = Keyword.put_new(spec, :field, field_name)
      {field_name, A.escape_expr(decoder_expr(spec, term_arg, result))}
    end)
  end

  defp decoder_expr(spec, term_arg, result) do
    cond do
      decode = Keyword.get(spec, :decode) ->
        decode

      Keyword.get(spec, :required, false) ->
        required_expr(spec, term_arg, result)

      Keyword.has_key?(spec, :default) ->
        "#{term_arg}.map_get(#{key!(spec)}).ok().and_then(|t| t.decode::<#{Rust.type(Keyword.fetch!(spec, :type))}>().ok()).unwrap_or(#{Keyword.fetch!(spec, :default)})"

      true ->
        "#{term_arg}.map_get(#{key!(spec)}).ok().and_then(|t| t.decode::<#{inner_option_type(Keyword.fetch!(spec, :type))}>().ok())"
    end
  end

  defp required_expr(spec, term_arg, :nif) do
    "#{term_arg}.map_get(#{key!(spec)})?.decode::<#{Rust.type(Keyword.fetch!(spec, :type))}>()?"
  end

  defp required_expr(spec, term_arg, _result) do
    field = Keyword.fetch!(spec, :field)
    type = Rust.type(Keyword.fetch!(spec, :type))
    missing = Keyword.get(spec, :missing, "Missing :#{field}")
    invalid = Keyword.get(spec, :invalid, "Invalid :#{field}")

    "#{term_arg}.map_get(#{key!(spec)}).map_err(|_| #{inspect(missing)}.to_string())?.decode::<#{type}>().map_err(|_| #{inspect(invalid)}.to_string())?"
  end

  defp key!(spec), do: Keyword.fetch!(spec, :key)

  defp inner_option_type({:option, type}), do: Rust.type(type)
  defp inner_option_type(type), do: Rust.type(type)

  defp result_type(name, lifetime, :nif), do: {:raw, "NifResult<#{name}<'#{lifetime}>>"}
  defp result_type(name, lifetime, result), do: {:raw, "#{result}<#{name}<'#{lifetime}>>"}

  defp ident_atom(value) when is_atom(value), do: value
  defp ident_atom(value) when is_binary(value), do: RustQ.Atom.identifier!(value)

  defp default_decoder_name(name), do: "decode_#{Macro.underscore(to_string(name))}"
end
