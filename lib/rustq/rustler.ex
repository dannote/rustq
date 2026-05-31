defmodule RustQ.Rustler do
  @moduledoc """
  Builders for common Rustler NIF declarations.
  """

  use RustQ.Sigil

  alias RustQ.Rust

  @resource_struct_template ~R"""
  struct __Resource {
      __splice_fields: (),
  }
  """

  @resource_impl_template ~R"""
  #[rustler::resource_impl]
  impl rustler::Resource for __Resource {}
  """

  @opts_struct_template ~R"""
  pub struct __Struct {
      __splice_fields: (),
  }
  """

  @opts_struct_lifetime_template ~R"""
  pub struct __Struct<'__lifetime> {
      __splice_fields: (),
  }
  """

  @opts_decoder_template ~R"""
  pub fn __decode_fn(__splice_args: ()) -> NifResult<__Struct> {
      Ok(__Struct {
          __splice_inits: (),
      })
  }
  """

  @opts_decoder_lifetime_template ~R"""
  pub fn __decode_fn<'__lifetime>(__splice_args: ()) -> NifResult<__Struct<'__lifetime>> {
      Ok(__Struct {
          __splice_inits: (),
      })
  }
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

  @spec init(module() | String.t()) :: Rust.Fragment.t()
  def init(module) when is_atom(module), do: init(Atom.to_string(module))
  def init(module) when is_binary(module), do: Rust.item(~s|rustler::init!("#{module}");|)

  @spec atoms([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          Rust.Fragment.t()
  def atoms(atoms, opts \\ []) do
    body =
      atoms
      |> Enum.map(&atom_decl/1)
      |> Enum.map_join("\n", fn decl -> "        #{decl}" end)

    module = Keyword.get(opts, :module, :atoms)
    code = ["rustler::atoms! {\n", body, "\n}"]

    case module do
      false -> Rust.item(code)
      module -> Rust.item(["mod ", to_string(module), " {\n", indent(code, 4), "\n}"])
    end
  end

  @spec resource(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def resource(name, opts \\ []) do
    fields =
      opts
      |> Keyword.get(:fields, [])
      |> Enum.map(fn {field, type} -> Rust.field(field, type, vis: :pub) end)

    [
      Rust.item(
        RustQ.render!(@resource_struct_template, "rustler_resource_struct.rs",
          bind: [Resource: name],
          splice: [fields: fields]
        )
      ),
      Rust.item(
        RustQ.render!(@resource_impl_template, "rustler_resource_impl.rs", bind: [Resource: name])
      )
    ]
  end

  @spec opts_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def opts_decoder(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)
    {struct_template, function_template} = opts_decoder_templates(lifetime)

    [
      Rust.item(
        RustQ.render!(struct_template, "rustler_opts_struct.rs",
          bind: opts_decoder_bindings(name, lifetime),
          splice: [fields: opts_decoder_fields(fields, phantom?, lifetime)]
        )
      ),
      Rust.item(
        RustQ.render!(function_template, "rustler_opts_decoder.rs",
          bind: opts_decoder_bindings(name, lifetime) ++ [decode_fn: function_name],
          splice: [
            args: [Rust.arg(:opts, {:raw, opts_arg_type(opts_arg)})],
            inits: opts_decoder_inits(fields, phantom?)
          ]
        )
      )
    ]
  end

  defp opts_decoder_templates(nil), do: {@opts_struct_template, @opts_decoder_template}

  defp opts_decoder_templates(_lifetime),
    do: {@opts_struct_lifetime_template, @opts_decoder_lifetime_template}

  defp opts_decoder_bindings(name, nil), do: [Struct: name]
  defp opts_decoder_bindings(name, lifetime), do: [Struct: name, lifetime: lifetime]

  defp opts_arg_type("opts: " <> type), do: type
  defp opts_arg_type(type), do: type

  defp opts_decoder_fields(fields, phantom?, lifetime) do
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

  defp opts_decoder_inits(fields, phantom?) do
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

  defp default_decoder_name(name) do
    "decode_#{Macro.underscore(to_string(name))}"
  end

  defp lifetime_generics(nil), do: ""
  defp lifetime_generics(lifetime), do: "<'#{lifetime}>"

  defp indent(iodata, spaces) do
    padding = String.duplicate(" ", spaces)

    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> padding <> line
    end)
  end

  defp nif_attr(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> "rustler::nif"
      :dirty_cpu -> ~s|rustler::nif(schedule = "DirtyCpu")|
      :dirty_io -> ~s|rustler::nif(schedule = "DirtyIo")|
      value when is_binary(value) -> ~s|rustler::nif(schedule = "#{value}")|
    end
  end

  defp atom_decl(name) when is_atom(name), do: "#{name},"
  defp atom_decl(name) when is_binary(name), do: "#{name},"

  defp atom_decl({name, value}) when (is_atom(name) or is_binary(name)) and is_binary(value),
    do: ~s|#{name} = "#{value}",|
end
