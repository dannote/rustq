defmodule RustQ.Rustler.OptsDecoder do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @struct_template ~R"""
  pub struct __Struct {
      __splice_fields: (),
  }
  """

  @struct_lifetime_template ~R"""
  pub struct __Struct<'__lifetime> {
      __splice_fields: (),
  }
  """

  @decoder_template ~R"""
  pub fn __decode_fn(__splice_args: ()) -> NifResult<__Struct> {
      Ok(__Struct {
          __splice_inits: (),
      })
  }
  """

  @decoder_lifetime_template ~R"""
  pub fn __decode_fn<'__lifetime>(__splice_args: ()) -> NifResult<__Struct<'__lifetime>> {
      Ok(__Struct {
          __splice_inits: (),
      })
  }
  """

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)
    {struct_template, function_template} = templates(lifetime)

    [
      Rust.item(
        RustQ.render!(struct_template, "rustler_opts_struct.rs",
          bind: bindings(name, lifetime),
          splice: [fields: fields(fields, phantom?, lifetime)]
        )
      ),
      Rust.item(
        RustQ.render!(function_template, "rustler_opts_decoder.rs",
          bind: bindings(name, lifetime) ++ [decode_fn: function_name],
          splice: [
            args: [Rust.arg(:opts, {:raw, opts_arg_type(opts_arg)})],
            inits: inits(fields, phantom?)
          ]
        )
      )
    ]
  end

  defp templates(nil), do: {@struct_template, @decoder_template}
  defp templates(_lifetime), do: {@struct_lifetime_template, @decoder_lifetime_template}

  defp bindings(name, nil), do: [Struct: name]
  defp bindings(name, lifetime), do: [Struct: name, lifetime: lifetime]

  defp opts_arg_type("opts: " <> type), do: type
  defp opts_arg_type(type), do: type

  defp fields(fields, phantom?, lifetime) do
    fields =
      Enum.map(fields, fn {field, spec} ->
        Rust.field(field, Keyword.fetch!(spec, :type), vis: :pub)
      end)

    if phantom? do
      fields ++ [Rust.field(:_phantom, {:raw, phantom_type(lifetime)})]
    else
      fields
    end
  end

  defp inits(fields, phantom?) do
    field_inits =
      Enum.map(fields, fn {field, spec} ->
        "#{field}: #{Keyword.fetch!(spec, :decode)}"
      end)

    if phantom? do
      field_inits ++ ["_phantom: std::marker::PhantomData"]
    else
      field_inits
    end
  end

  defp phantom_type(nil), do: "std::marker::PhantomData<()>"
  defp phantom_type(lifetime), do: "std::marker::PhantomData<&'#{lifetime} ()>"

  defp default_decoder_name(name), do: "decode_#{Macro.underscore(to_string(name))}"
  defp lifetime_generics(nil), do: ""
  defp lifetime_generics(lifetime), do: "<'#{lifetime}>"
end
