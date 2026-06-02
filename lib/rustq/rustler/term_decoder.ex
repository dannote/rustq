defmodule RustQ.Rustler.TermDecoder do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @struct_template ~R"""
  struct __rq_Struct<'__rq_lifetime> {
      __rq_fields: (),
  }
  """

  @function_template ~R"""
  fn __rq_decode_fn<'__rq_lifetime>(__rq_args: ()) -> __rq_result!() {
      Ok(__rq_Struct {
          __rq_inits: (),
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

    result = Keyword.get(opts, :result, :nif)
    result_type = result_type(name, lifetime, result)

    bindings = [
      Struct: name,
      lifetime: lifetime,
      decode_fn: function_name,
      result: Rust.type(result_type)
    ]

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
            inits: decoder_inits(fields, term_arg, result)
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

  defp decoder_inits(fields, term_arg, result) do
    Enum.map(fields, fn {field, spec} ->
      spec = Keyword.put_new(spec, :field, field)
      "#{field}: #{decoder_expr(spec, term_arg, result)}"
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

  defp default_decoder_name(name), do: "decode_#{Macro.underscore(to_string(name))}"
end
