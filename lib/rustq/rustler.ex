defmodule RustQ.Rustler do
  @moduledoc """
  Builders for common Rustler NIF declarations.
  """

  alias RustQ.Rust

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

    struct_template = """
    struct __Resource {
        __splice_fields: (),
    }
    """

    impl_template = """
    #[rustler::resource_impl]
    impl rustler::Resource for __Resource {}
    """

    [
      Rust.item(
        RustQ.render!(struct_template, "rustler_resource_struct.rs",
          bind: [Resource: name],
          splice: [fields: fields]
        )
      ),
      Rust.item(RustQ.render!(impl_template, "rustler_resource_impl.rs", bind: [Resource: name]))
    ]
  end

  @spec opts_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def opts_decoder(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)

    [struct_template, function_template] = opts_decoder_templates(lifetime, opts_arg)

    [
      Rust.item(
        RustQ.render!(struct_template, "rustler_opts_struct.rs",
          bind: [Struct: name],
          splice: [fields: opts_decoder_fields(fields)]
        )
      ),
      Rust.item(
        RustQ.render!(function_template, "rustler_opts_decoder.rs",
          bind: [Struct: name, decode_fn: function_name],
          splice: [inits: opts_decoder_inits(fields, phantom?)]
        )
      )
    ]
  end

  defp opts_decoder_templates(nil, opts_arg) do
    [
      """
      pub struct __Struct {
          __splice_fields: (),
      }
      """,
      """
      pub fn __decode_fn(#{opts_arg}) -> NifResult<__Struct> {
          Ok(__Struct {
              __splice_inits: (),
          })
      }
      """
    ]
  end

  defp opts_decoder_templates(lifetime, opts_arg) do
    [
      """
      pub struct __Struct<'#{lifetime}> {
          __splice_fields: (),
      }
      """,
      """
      pub fn __decode_fn<'#{lifetime}>(#{opts_arg}) -> NifResult<__Struct<'#{lifetime}>> {
          Ok(__Struct {
              __splice_inits: (),
          })
      }
      """
    ]
  end

  defp opts_decoder_fields(fields) do
    Enum.map(fields, fn {field, spec} ->
      Rust.field(field, Keyword.fetch!(spec, :type), vis: :pub)
    end)
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
