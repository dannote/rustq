defmodule RustQ.Rustler.TermDecoder do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @struct_template ~R"""
  struct __Struct<'__lifetime> {
      __splice_fields: (),
  }
  """

  @function_template ~R"""
  fn __decode_fn<'__lifetime>(__splice_args: ()) -> NifResult<__Struct<'__lifetime>> {
      Ok(__Struct {
          __splice_inits: (),
      })
  }
  """

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    lifetime = Keyword.get(opts, :lifetime, :a)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    term_arg = Keyword.get(opts, :term_arg, :term)
    term_type = Keyword.get(opts, :term_type, "Term<'#{lifetime}>")

    bindings = [Struct: name, lifetime: lifetime, decode_fn: function_name]

    [
      Rust.item(
        RustQ.render!(@struct_template, "rustler_term_decoder_struct.rs",
          bind: bindings,
          splice: [fields: struct_fields(fields)]
        )
      ),
      Rust.item(
        RustQ.render!(@function_template, "rustler_term_decoder_fn.rs",
          bind: bindings,
          splice: [
            args: [Rust.arg(term_arg, {:raw, term_type})],
            inits: decoder_inits(fields, term_arg)
          ]
        )
      )
    ]
  end

  defp struct_fields(fields) do
    Enum.map(fields, fn {field, spec} ->
      Rust.field(field, Keyword.fetch!(spec, :type))
    end)
  end

  defp decoder_inits(fields, term_arg) do
    Enum.map(fields, fn {field, spec} ->
      "#{field}: #{decoder_expr(spec, term_arg)}"
    end)
  end

  defp decoder_expr(spec, term_arg) do
    cond do
      decode = Keyword.get(spec, :decode) ->
        decode

      Keyword.get(spec, :required, false) ->
        "#{term_arg}.map_get(#{key!(spec)})?.decode::<#{Rust.type(Keyword.fetch!(spec, :type))}>()?"

      Keyword.has_key?(spec, :default) ->
        "#{term_arg}.map_get(#{key!(spec)}).ok().and_then(|t| t.decode::<#{Rust.type(Keyword.fetch!(spec, :type))}>().ok()).unwrap_or(#{Keyword.fetch!(spec, :default)})"

      true ->
        "#{term_arg}.map_get(#{key!(spec)}).ok().and_then(|t| t.decode::<#{inner_option_type(Keyword.fetch!(spec, :type))}>().ok())"
    end
  end

  defp key!(spec), do: Keyword.fetch!(spec, :key)

  defp inner_option_type({:option, type}), do: Rust.type(type)
  defp inner_option_type(type), do: Rust.type(type)

  defp default_decoder_name(name), do: "decode_#{Macro.underscore(to_string(name))}"
end
