defmodule RustQ.Native do
  @moduledoc """
  Builds and loads a Rustler NIF crate generated entirely from Rusty-Elixir.

  `use RustQ.Native` makes the current module a native compilation unit and
  imports `RustQ.Meta`. Public entrypoints use `defnif`; generated helper
  functions use `defrust` or `defrustp`.

      defmodule MyApp.Native do
        use RustQ.Native

        @spec add(integer(), integer()) :: integer()
        defnif add(left, right), do: left + right
      end

  RustQ generates the crate under the Mix build directory, compiles it with
  Cargo, copies the native library into the application's `priv/native`
  directory, and injects the NIF loader. No checked-in Rust or Cargo files are
  required for this path.

  Genuine native policy remains explicit. Use `:otp_app`, `:crate`, `:mode`,
  or `:cargo` only when their inferred defaults are not appropriate. Existing
  `RustQ.Meta` options such as `:rust_sources`, `:rust_packages`, and
  `:callable_modules` may be passed alongside them.
  """

  alias RustQ.Meta.{Options, Type}
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.Walk
  alias RustQ.Rust.Identifier
  alias RustQ.Rustler.Nif

  @native_options [:otp_app, :crate, :mode, :cargo, :crates]

  @doc false
  defmacro __using__(opts) do
    native_opts = native_options!(opts, __CALLER__)
    manifest = prepare_manifest!(native_opts)

    package_metadata =
      Enum.map(native_opts[:crates], fn {package, _spec} ->
        {package, manifest_path: manifest}
      end)

    meta_opts =
      opts
      |> Keyword.drop(@native_options)
      |> Keyword.update(:rust_packages, package_metadata, &(List.wrap(&1) ++ package_metadata))

    rust_modules =
      Enum.map(native_opts[:crates], fn {package, _spec} ->
        normalized = String.replace(package, "-", "_")
        alias_name = normalized |> Macro.camelize() |> Identifier.atom!()
        {[alias_name], [Identifier.atom!(normalized)]}
      end)

    quote do
      Module.register_attribute(__MODULE__, :rustq_native_opts, persist: true)
      @rustq_native_opts unquote(Macro.escape(native_opts))
      use RustQ.Meta, unquote(meta_opts)

      for mapping <- unquote(Macro.escape(rust_modules)) do
        @rustq_mod_aliases mapping
      end
    end
  end

  @doc false
  def __compile_native__(env, values, opts, exports) do
    module = env.module
    crate = Keyword.fetch!(opts, :crate)
    otp_app = Keyword.fetch!(opts, :otp_app)
    mode = Keyword.fetch!(opts, :mode)
    cargo = Keyword.fetch!(opts, :cargo)

    root = Path.join([Mix.Project.build_path(), "rustq_native", crate])
    manifest = Path.join(root, "Cargo.toml")
    source_path = Path.join([root, "src", "lib.rs"])
    target = Path.join(root, "target")

    source = native_source(native_items(values), module)

    write_if_changed!(manifest, cargo_manifest(crate, opts[:crates]))
    write_if_changed!(source_path, source)
    build_crate!(cargo, manifest, target, mode, module)

    destination = install_library!(target, mode, crate, otp_app)
    relative_library = Path.join("priv/native", Path.rootname(Path.basename(destination)))

    loader =
      quote do
        @on_load :__rustq_load_nif__

        @doc false
        def __rustq_load_nif__ do
          :code.purge(__MODULE__)

          path =
            unquote(otp_app)
            |> Application.app_dir(unquote(relative_library))
            |> to_charlist()

          :erlang.load_nif(path, 0)
        end
      end

    quote do
      unquote(exports)
      unquote(loader)
    end
  end

  defp native_options!(opts, caller) when is_list(opts) do
    unknown = Keyword.keys(opts) -- (@native_options ++ Options.option_names())

    if unknown != [] do
      raise ArgumentError, "unknown RustQ.Native options: #{inspect(unknown)}"
    end

    otp_app = opts |> Keyword.get_lazy(:otp_app, &default_otp_app!/0) |> Macro.expand(caller)

    crate =
      opts
      |> Keyword.get_lazy(:crate, fn -> default_crate(caller.module) end)
      |> Macro.expand(caller)

    mode = opts |> Keyword.get_lazy(:mode, &default_mode/0) |> Macro.expand(caller)
    cargo = opts |> Keyword.get(:cargo, "cargo") |> Macro.expand(caller)
    crates = opts |> Keyword.get(:crates, []) |> Macro.expand(caller) |> normalize_crates!()

    unless is_atom(otp_app), do: raise(ArgumentError, ":otp_app must be an atom")

    unless mode in [:debug, :release],
      do: raise(ArgumentError, ":mode must be :debug or :release")

    unless is_binary(cargo), do: raise(ArgumentError, ":cargo must be an executable path")

    crate = crate |> to_string() |> normalize_crate!()

    [otp_app: otp_app, crate: crate, mode: mode, cargo: cargo, crates: crates]
  end

  defp default_otp_app! do
    Mix.Project.config()[:app] ||
      raise ArgumentError, "RustQ.Native could not infer :otp_app from the current Mix project"
  end

  defp default_crate(module) do
    module
    |> Module.split()
    |> Enum.map_join("_", &Macro.underscore/1)
  end

  defp default_mode, do: if(Mix.env() == :prod, do: :release, else: :debug)

  defp normalize_crate!(crate) do
    crate = String.replace(crate, "-", "_")

    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, crate) do
      crate
    else
      raise ArgumentError, "invalid generated Cargo crate name #{inspect(crate)}"
    end
  end

  defp native_items(values) do
    map_structs =
      values[:type_aliases]
      |> Enum.flat_map(fn
        {_key, %Type{kind: :struct, meta: %{representation: :map} = meta}} ->
          [to_string(meta.rust_name)]

        _type ->
          []
      end)
      |> MapSet.new()

    nif_structs =
      values[:type_aliases]
      |> Enum.flat_map(fn
        {_key,
         %Type{
           kind: :struct,
           meta: %{representation: :struct, rust_name: name, elixir_module: module}
         }} ->
          [{to_string(name), module}]

        _type ->
          []
      end)
      |> Map.new()

    unit_enums =
      values[:type_aliases]
      |> Enum.flat_map(fn
        {_key, %Type{kind: :enum} = type} ->
          [{to_string(type.rust), "decode_#{type.meta.elixir_name}_atom"}]

        _type ->
          []
      end)
      |> Map.new()

    generated_decoders =
      map_structs
      |> MapSet.union(MapSet.new(Map.keys(nif_structs)))
      |> MapSet.new(fn name -> "decode_#{Macro.underscore(name)}" end)
      |> MapSet.union(MapSet.new(Map.values(unit_enums)))

    Enum.flat_map(values[:items], fn
      %AST.Struct{name: name} = struct ->
        name = to_string(name)

        cond do
          MapSet.member?(map_structs, name) ->
            [%{struct | derive: Enum.uniq(struct.derive ++ ["rustler::NifMap"])}]

          module = Map.get(nif_structs, name) ->
            [
              %{
                struct
                | derive: Enum.uniq(struct.derive ++ ["rustler::NifStruct"]),
                  attrs: Enum.uniq(struct.attrs ++ [A.attr_value(:module, module_name(module))])
              }
            ]

          true ->
            [struct]
        end

      %AST.Enum{name: name} = enum ->
        if Map.has_key?(unit_enums, to_string(name)) do
          [%{enum | derive: Enum.uniq(enum.derive ++ ["rustler::NifUnitEnum"])}]
        else
          [enum]
        end

      %AST.Function{name: name} = function ->
        if MapSet.member?(generated_decoders, to_string(name)) do
          []
        else
          [add_generated_clippy_allows(function)]
        end

      item ->
        [item]
    end)
  end

  defp add_generated_clippy_allows(%AST.Function{} = function) do
    lints =
      Walk.reduce(function.body, MapSet.new(), fn
        %AST.MethodCall{method: :filter_map}, lints ->
          MapSet.put(lints, [:clippy, :unnecessary_filter_map])

        %AST.MethodCall{method: :fold}, lints ->
          MapSet.put(lints, [:clippy, :unnecessary_fold])

        %AST.Match{arms: [_single]}, lints ->
          MapSet.put(lints, [:clippy, :match_single_binding])

        %AST.PatStruct{}, lints ->
          MapSet.put(lints, [:non_shorthand_field_patterns])

        _node, lints ->
          lints
      end)

    if MapSet.size(lints) == 0 do
      function
    else
      allow = A.attr(:allow, lints |> Enum.sort() |> Enum.map(&A.path/1))
      %{function | attrs: Enum.uniq(function.attrs ++ [allow])}
    end
  end

  defp module_name(module), do: module |> Module.split() |> Enum.join(".")

  defp prepare_manifest!(opts) do
    root = Path.join([Mix.Project.build_path(), "rustq_native", opts[:crate]])
    manifest = Path.join(root, "Cargo.toml")
    source = Path.join([root, "src", "lib.rs"])
    write_if_changed!(manifest, cargo_manifest(opts[:crate], opts[:crates]))

    unless File.exists?(source) do
      write_if_changed!(source, "// RustQ.Native source is generated before Cargo compilation.\n")
    end

    manifest
  end

  defp native_source(items, module) do
    imports = A.use({[:rustler], [:Atom, :Binary, :Decoder, :Encoder, :Env, :NifResult, :Term]})

    body =
      [imports | items]
      |> Kernel.++([Nif.init(module)])
      |> Enum.map_join("\n\n", &(&1 |> RustQ.Rust.render() |> String.trim()))

    "// Generated by RustQ.Native. Do not edit.\n#![allow(unused_imports)]\n\n#{body}\n"
  end

  defp cargo_manifest(crate, crates) do
    dependencies =
      crates
      |> Enum.map_join("\n", fn {package, spec} ->
        "#{package} = #{cargo_dependency(spec)}"
      end)

    """
    [package]
    name = "#{crate}"
    version = "0.1.0"
    edition = "2021"
    publish = false

    [lib]
    name = "#{crate}"
    crate-type = ["cdylib"]

    [dependencies]
    rustler = "0.37"
    #{dependencies}
    """
  end

  defp normalize_crates!(crates) when is_list(crates) do
    Enum.map(crates, fn
      {package, version} when (is_atom(package) or is_binary(package)) and is_binary(version) ->
        {to_string(package), version}

      {package, spec} when (is_atom(package) or is_binary(package)) and is_list(spec) ->
        {to_string(package), spec}

      other ->
        raise ArgumentError,
              ":crates must be a keyword/list of package names to version strings or options, got: #{inspect(other)}"
    end)
  end

  defp normalize_crates!(other),
    do: raise(ArgumentError, ":crates must be a keyword list, got: #{inspect(other)}")

  defp cargo_dependency(version) when is_binary(version), do: inspect(version)

  defp cargo_dependency(opts) when is_list(opts) do
    entries =
      opts
      |> Enum.map(fn
        {:version, value} when is_binary(value) -> "version = #{inspect(value)}"
        {:path, value} when is_binary(value) -> "path = #{inspect(Path.expand(value))}"
        {:git, value} when is_binary(value) -> "git = #{inspect(value)}"
        {:branch, value} when is_binary(value) -> "branch = #{inspect(value)}"
        {:tag, value} when is_binary(value) -> "tag = #{inspect(value)}"
        {:rev, value} when is_binary(value) -> "rev = #{inspect(value)}"
        {:features, values} when is_list(values) -> "features = #{inspect(values)}"
        {:default_features, value} when is_boolean(value) -> "default-features = #{value}"
        other -> raise ArgumentError, "unsupported Cargo dependency option #{inspect(other)}"
      end)

    "{ #{Enum.join(entries, ", ")} }"
  end

  defp write_if_changed!(path, content) do
    if not File.exists?(path) or File.read!(path) != content do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end
  end

  defp build_crate!(cargo, manifest, target, mode, module) do
    args =
      ["build", "--manifest-path", manifest] ++ if(mode == :release, do: ["--release"], else: [])

    {output, status} =
      System.cmd(cargo, args,
        env: [{"CARGO_TARGET_DIR", target}],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise CompileError,
        description:
          "generated RustQ.Native crate for #{inspect(module)} failed to compile:\n#{output}"
    end
  end

  defp install_library!(target, mode, crate, otp_app) do
    profile = if mode == :release, do: "release", else: "debug"
    source = Path.join([target, profile, library_filename(crate)])

    unless File.regular?(source) do
      raise CompileError, description: "Cargo did not produce expected native library #{source}"
    end

    destination_dir = Path.join(Mix.Project.app_path(), "priv/native")
    destination = Path.join(destination_dir, Path.basename(source))
    File.mkdir_p!(destination_dir)
    File.cp!(source, destination)

    # Keep the owning application visible in the stack trace if installation
    # fails while compiling an umbrella child.
    _ = otp_app
    destination
  end

  defp library_filename(crate) do
    case :os.type() do
      {:win32, _} -> "#{crate}.dll"
      {:unix, :darwin} -> "lib#{crate}.dylib"
      _other -> "lib#{crate}.so"
    end
  end
end
