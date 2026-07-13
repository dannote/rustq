defmodule RustQ.Rustler.Nif do
  @moduledoc """
  Generates Rustler NIF exports, NifStruct declarations, and raw NIF_TERM builders.

  Most helpers in this module use RustQ AST. The raw `NIF_TERM` builders are an
  explicit low-level Rustler escape boundary for unsafe wrapper APIs; prefer
  `RustQ.Rustler.Term` helpers when normal `Term<'a>` values are available.
  """

  use RustQ.Sigil

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I
  alias RustQ.Syn.{Arg, Type}

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3]
  import RustQ.Rust.AST.ItemBuilder

  require A
  require I
  require RustQ.Rust.AST.ItemBuilder

  @type spec :: {atom() | String.t(), keyword()}

  @nif_term_builder_names [:map_from_nif_terms, :struct_from_nif_terms]

  @nif_term_builder_templates %{
    map_from_nif_terms: ~R"""
    fn make_map_from_nif_terms<'a>(
        env: Env<'a>,
        pairs: &[(rustler::wrapper::NIF_TERM, rustler::wrapper::NIF_TERM)],
    ) -> NifResult<Term<'a>> {
        let mut map = unsafe { rustler::wrapper::map::map_new(env.as_c_arg()) };

        for (key, value) in pairs {
            map = unsafe { rustler::wrapper::map::map_put(env.as_c_arg(), map, *key, *value) }
                .ok_or(rustler::Error::BadArg)?;
        }

        Ok(unsafe { Term::new(env, map) })
    }
    """,
    struct_from_nif_terms: ~R"""
    fn make_struct_from_nif_terms<'a>(
        env: Env<'a>,
        keys: &[rustler::wrapper::NIF_TERM],
        values: &[rustler::wrapper::NIF_TERM],
    ) -> NifResult<Term<'a>> {
        if keys.len() != values.len() {
            return Err(rustler::Error::BadArg);
        }

        let mut map = unsafe { rustler::wrapper::map::map_new(env.as_c_arg()) };

        for (key, value) in keys.iter().zip(values.iter()) {
            map = unsafe { rustler::wrapper::map::map_put(env.as_c_arg(), map, *key, *value) }
                .ok_or(rustler::Error::BadArg)?;
        }

        Ok(unsafe { Term::new(env, map) })
    }
    """
  }

  @spec struct(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  def struct(name, module, opts \\ []) do
    ast =
      I.struct RustQ.Atom.identifier!(to_string(name)),
        vis: Keyword.get(opts, :vis, :pub),
        derive: Keyword.get(opts, :derive, [:Clone, :Debug, :NifStruct]),
        attrs: [
          A.attr_value(:module, module_name(module))
          | normalize_attrs(Keyword.get(opts, :attrs, []))
        ] do
        struct_fields(Keyword.get(opts, :fields, []), Keyword.get(opts, :field_vis, :pub))
      end

    Rust.ast_item(ast)
  end

  @spec exports([spec()]) :: [Rust.Function.t()]
  def exports(specs) do
    Enum.map(specs, fn {name, opts} -> wrapper(name, opts) end)
  end

  @spec exports_from_source(Path.t(), [spec()], keyword()) :: [Rust.Function.t()]
  def exports_from_source(path, specs, defaults \\ []) do
    path
    |> source_exports(specs, defaults)
    |> Enum.map(fn {name, function, opts} ->
      derived = [
        args: Enum.map(function.args, &source_arg/1),
        returns: function.returns || :unit
      ]

      wrapper(name, Keyword.merge(derived, opts))
    end)
  end

  @spec stubs_from_source(Path.t(), [spec()], module(), keyword()) :: String.t()
  def stubs_from_source(path, specs, module, defaults \\ []) do
    functions =
      path
      |> source_exports(specs, defaults)
      |> Enum.map(fn {name, function, _opts} -> {name, function} end)

    stubs_from_functions(functions, module)
  end

  @spec stubs_from_functions(
          [RustQ.Syn.Function.t() | AST.Function.t() | {term(), term()}],
          module()
        ) ::
          String.t()
  def stubs_from_functions(functions, module) do
    definitions = Enum.map(functions, &stub_definition/1)
    quoted_body = {:quote, [], [[do: {:__block__, [], definitions}]]}

    quote do
      defmodule unquote(module) do
        @moduledoc false
        defmacro __using__(_opts), do: unquote(quoted_body)
      end
    end
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  @spec export(atom() | String.t(), keyword()) :: Rust.Function.t()
  def export(name, opts), do: wrapper(name, opts)

  @spec term_builders(keyword()) :: [Rust.Fragment.t()]
  def term_builders(opts \\ []) do
    opts
    |> Keyword.get(:include, @nif_term_builder_names)
    |> include_names()
    |> Enum.map(
      &Rust.item(RustQ.render!(nif_term_builder_template!(&1), "rustler_nif_term_builder.rs"))
    )
  end

  @doc false
  @spec nif_attr(keyword()) :: String.t()
  def nif_attr(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> "rustler::nif"
      :dirty_cpu -> ~s|rustler::nif(schedule = "DirtyCpu")|
      :dirty_io -> ~s|rustler::nif(schedule = "DirtyIo")|
      value when is_binary(value) -> ~s|rustler::nif(schedule = "#{value}")|
    end
  end

  defp struct_fields(fields, default_vis) do
    Enum.map(fields, fn
      %RustQ.Rust.Field{} = rust_field ->
        field(RustQ.Atom.identifier!(to_string(rust_field.name)), rust_field.type,
          vis: rust_field.vis
        )

      {field_name, type} ->
        field(field_name, type, vis: default_vis)
    end)
  end

  defp normalize_attrs(attrs), do: Enum.map(attrs, &normalize_attr/1)
  defp normalize_attr(%AST.Attribute{} = attr), do: attr

  defp normalize_attr(attr) when is_list(attr),
    do: attr |> IO.iodata_to_binary() |> normalize_attr()

  defp normalize_attr(attr) when is_binary(attr) do
    cond do
      String.contains?(attr, " = ") ->
        [path, value] = String.split(attr, " = ", parts: 2)
        A.attr_value(RustQ.Atom.identifier!(path), String.trim(value, ~s|"|))

      String.ends_with?(attr, ")") and String.contains?(attr, "(") ->
        [path, args] = String.split(String.trim_trailing(attr, ")"), "(", parts: 2)

        args =
          args
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.map(&RustQ.Atom.identifier!/1)

        A.attr(RustQ.Atom.identifier!(path), args)

      true ->
        A.attr(RustQ.Atom.identifier!(attr))
    end
  end

  defp wrapper(name, opts) do
    args = Keyword.get(opts, :args, [])
    impl = Keyword.get(opts, :impl, "#{name}_impl")
    call_args = args |> Keyword.keys() |> Enum.map_join(", ", &to_string/1)

    if ast_compatible?(opts) do
      ast =
        function RustQ.Atom.identifier!(to_string(name)),
          args: args,
          returns: Keyword.fetch!(opts, :returns),
          lifetime: Keyword.get(opts, :lifetime),
          vis: Keyword.get(opts, :vis),
          attrs: normalize_attrs(Keyword.get(opts, :attrs, [])) ++ [nif_attribute(opts)] do
          A.return(A.call(RustQ.Atom.identifier!(to_string(impl)), Keyword.keys(args)))
        end

      Rust.ast_item(ast)
    else
      name
      |> Rust.fn(
        args: args,
        returns: Keyword.get(opts, :returns),
        lifetime: Keyword.get(opts, :lifetime),
        lifetimes: Keyword.get(opts, :lifetimes, []),
        generics: Keyword.get(opts, :generics, []),
        where: Keyword.get(opts, :where, []),
        body: "#{impl}(#{call_args})",
        vis: Keyword.get(opts, :vis)
      )
      |> Rust.attr(nif_attr(opts))
    end
  end

  defp source_exports(path, specs, defaults) do
    functions = path |> RustQ.Syn.parse_file!() |> RustQ.Syn.functions()

    Enum.map(specs, fn {name, opts} ->
      opts = Keyword.merge(defaults, opts)
      impl = Keyword.get(opts, :impl, "#{name}_impl")
      function = Enum.find(functions, &(&1.name == to_string(impl)))

      if function do
        {name, function, Keyword.put(opts, :impl, impl)}
      else
        raise ArgumentError, "NIF implementation #{impl} not found in #{path}"
      end
    end)
  end

  defp source_arg(%Arg{name: name, type: type}) when is_binary(name),
    do: {RustQ.Atom.identifier!(name), type}

  defp stub_definition({name, function}) do
    stub_definition(function, name)
  end

  defp stub_definition(%{name: name} = function), do: stub_definition(function, name)

  defp stub_definition(function, name) do
    args = function |> stub_args() |> Enum.map(&stub_arg/1)

    quote do
      def unquote(RustQ.Atom.identifier!(to_string(name)))(unquote_splicing(args)),
        do: :erlang.nif_error(:nif_not_loaded)
    end
  end

  defp stub_args(%RustQ.Syn.Function{args: args}), do: Enum.reject(args, &env_arg?/1)

  defp stub_args(%AST.Function{args: args}) do
    Enum.reject(args, fn
      %AST.FunctionArg{receiver: true} -> true
      %AST.FunctionArg{type: type} -> ast_env_type?(type)
    end)
  end

  defp env_arg?(%Arg{type_ast: type}), do: Type.path?(type, "Env")

  defp ast_env_type?(%AST.TypePath{parts: parts}), do: to_string(List.last(parts)) == "Env"
  defp ast_env_type?(_type), do: false

  defp stub_arg(%{name: name}) do
    RustQ.Atom.identifier!("_#{name}")
    |> then(&{&1, [], nil})
  end

  defp ast_compatible?(opts) do
    impl = Keyword.get(opts, :impl)

    Keyword.has_key?(opts, :returns) and Keyword.get(opts, :lifetimes, []) == [] and
      Keyword.get(opts, :generics, []) == [] and Keyword.get(opts, :where, []) == [] and
      (is_nil(impl) or simple_ident?(impl))
  end

  defp simple_ident?(value), do: value |> to_string() |> RustQ.Atom.identifier?()

  defp nif_attribute(opts) do
    case Keyword.get(opts, :schedule) do
      nil -> A.nif_attr()
      :dirty_cpu -> A.nif_attr(schedule: "DirtyCpu")
      :dirty_io -> A.nif_attr(schedule: "DirtyIo")
      value when is_binary(value) -> A.nif_attr(schedule: value)
    end
  end

  defp include_names(:all), do: @nif_term_builder_names
  defp include_names(names), do: List.wrap(names)

  defp nif_term_builder_template!(name), do: Map.fetch!(@nif_term_builder_templates, name)

  defp module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp module_name(module) when is_binary(module), do: module
end
