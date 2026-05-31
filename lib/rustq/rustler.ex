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
    fields = Keyword.get(opts, :fields, [])

    [
      Rust.item([
        "struct ",
        to_string(name),
        " {\n",
        Enum.map(fields, fn {field, type} ->
          ["pub ", to_string(field), ": ", Rust.type(type), ",\n"]
        end),
        "}"
      ]),
      Rust.item([
        "#[rustler::resource_impl]\nimpl rustler::Resource for ",
        to_string(name),
        " {}"
      ])
    ]
  end

  @spec opts_decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def opts_decoder(name, opts) do
    lifetime = Keyword.get(opts, :lifetime)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    opts_arg = Keyword.get(opts, :opts_arg, "opts: &[(Atom, Term#{lifetime_generics(lifetime)})]")
    result_type = [to_string(name), lifetime_generics(lifetime)]
    phantom? = Keyword.get(opts, :phantom, lifetime != nil)

    [
      Rust.item([
        "pub struct ",
        to_string(name),
        lifetime_generics(lifetime),
        " {\n",
        Enum.map(fields, fn {field, spec} ->
          ["pub ", to_string(field), ": ", Rust.type(Keyword.fetch!(spec, :type)), ",\n"]
        end),
        phantom_field(phantom?, lifetime),
        "}"
      ]),
      Rust.item([
        "pub fn ",
        to_string(function_name),
        lifetime_generics(lifetime),
        "(",
        opts_arg,
        ") -> NifResult<",
        result_type,
        "> {\nOk(",
        to_string(name),
        " {\n",
        Enum.map(fields, fn {field, spec} ->
          [to_string(field), ": ", Keyword.fetch!(spec, :decode), ",\n"]
        end),
        phantom_init(phantom?),
        "})\n}"
      ])
    ]
  end

  defp default_decoder_name(name) do
    "decode_#{Macro.underscore(to_string(name))}"
  end

  defp lifetime_generics(nil), do: ""
  defp lifetime_generics(lifetime), do: "<'#{lifetime}>"

  defp phantom_field(false, _lifetime), do: []
  defp phantom_field(true, nil), do: "_phantom: std::marker::PhantomData<()>,\n"

  defp phantom_field(true, lifetime),
    do: "_phantom: std::marker::PhantomData<&'#{lifetime} ()>,\n"

  defp phantom_init(false), do: []
  defp phantom_init(true), do: "_phantom: std::marker::PhantomData,\n"

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
