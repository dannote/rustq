defmodule RustQ.Binding.Source do
  @moduledoc """
  Resolves callable metadata from RustQ modules, Rust source files, and Cargo packages.

  This module is the source-backed callable metadata boundary used by
  `RustQ.Meta`. It keeps parsing, package indexing, alias-equivalence annotation,
  caching, and configuration diagnostics out of the macro frontend.
  """

  alias RustQ.Binding.Callable
  alias RustQ.Diagnostic
  alias RustQ.Meta.Type
  alias RustQ.Syn

  @type rust_package :: String.t() | {String.t(), keyword()}

  @doc "Resolves external callable metadata configured on a `use RustQ.Meta` module."
  @spec external_callables(module()) :: [Callable.t()]
  def external_callables(module) when is_atom(module) do
    rust_source_callables_for_module(module) ++
      rust_package_callables_for_module(module) ++
      callable_module_callables(module)
  end

  @doc "Expands Rust source paths relative to the current project working directory."
  @spec rust_source_paths([Path.t()] | Path.t() | nil) :: [Path.t()]
  def rust_source_paths(paths) do
    paths
    |> List.wrap()
    |> Enum.map(&rust_source_path/1)
  end

  defp rust_source_path(path) when is_binary(path) do
    if Path.type(path) == :absolute, do: path, else: Path.expand(path, File.cwd!())
  end

  defp rust_source_callables_for_module(module) do
    module
    |> Module.get_attribute(:rustq_rust_sources)
    |> List.wrap()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&cached_rust_source_callables/1)
  end

  defp callable_module_callables(module) do
    module
    |> Module.get_attribute(:rustq_callable_modules)
    |> List.wrap()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&cached_callable_module_callables/1)
  end

  defp cached_callable_module_callables(module),
    do: cached_callables({:callable_module, module}, fn -> callable_module_callables!(module) end)

  defp callable_module_callables!(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        unless function_exported?(module, :__rustq_callables__, 0) do
          Diagnostic.defrust(
            :invalid_callable_module,
            module,
            "configured RustQ callable module does not expose __rustq_callables__/0",
            details: %{module: module}
          )
        end

        module.__rustq_callables__()

      {:error, reason} ->
        Diagnostic.defrust(
          :callable_module_compile_failed,
          module,
          "configured RustQ callable module could not be compiled",
          details: %{module: module, reason: reason}
        )
    end
  end

  defp cached_rust_source_callables(path) do
    fingerprint = rust_source_fingerprint(path)
    cache_key = {__MODULE__, :callables, {:rust_source, path}}

    case :persistent_term.get(cache_key, :missing) do
      {:rust_source, ^fingerprint, callables} ->
        callables

      _missing_or_stale ->
        callables = rust_source_callables(path)
        :persistent_term.put(cache_key, {:rust_source, fingerprint, callables})
        callables
    end
  end

  defp rust_source_fingerprint(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        {mtime, size}

      {:error, _reason} ->
        :missing
    end
  end

  defp rust_source_callables(path) do
    unless File.regular?(path) do
      Diagnostic.defrust(:invalid_rust_source, path, "configured Rust source does not exist",
        details: %{path: path}
      )
    end

    file =
      try do
        Syn.parse_file!(path)
      rescue
        error in [RustQ.Error, File.Error, ArgumentError, RuntimeError] ->
          Diagnostic.defrust(
            :rust_source_parse_failed,
            path,
            "configured Rust source could not be parsed",
            details: %{path: path, error: error}
          )
      end

    function_callables = file |> Syn.functions() |> Enum.map(&Callable.from_syn_function/1)
    method_callables = file |> Syn.impls() |> Enum.flat_map(&impl_callables/1)

    function_callables ++ method_callables
  end

  defp rust_package_callables_for_module(module) do
    module
    |> Module.get_attribute(:rustq_rust_packages)
    |> List.wrap()
    |> List.flatten()
    |> Enum.flat_map(&cached_rust_package_callables/1)
  end

  defp cached_rust_package_callables(config),
    do: cached_callables({:rust_package, config}, fn -> rust_package_callables(config) end)

  defp rust_package_callables({package, opts}) when is_binary(package) and is_list(opts) do
    index =
      try do
        Syn.Index.cached_package(package, opts)
      rescue
        error in [RustQ.Error, Mix.Error, ArgumentError, RuntimeError] ->
          Diagnostic.defrust(
            :rust_package_load_failed,
            package,
            "configured Rust package could not be loaded",
            details: %{package: package, opts: opts, error: error}
          )
      end

    index
    |> Syn.Index.impls()
    |> Enum.flat_map(&impl_callables/1)
    |> Enum.map(&annotate_callable_public_aliases(&1, index))
  end

  defp rust_package_callables(package) when is_binary(package),
    do: rust_package_callables({package, []})

  defp impl_callables(%Syn.Impl{} = impl) do
    Enum.map(impl.methods, &Callable.from_syn_method(&1, target: impl.target))
  end

  defp annotate_callable_public_aliases(%Callable{} = callable, %Syn.Index{} = index) do
    %{
      callable
      | args: Enum.map(callable.args, &annotate_callable_arg(&1, index)),
        returns: annotate_public_alias_type(callable.returns, index)
    }
  end

  defp annotate_callable_arg(%{type: type} = arg, index),
    do: %{arg | type: annotate_public_alias_type(type, index)}

  defp annotate_public_alias_type(%Type{kind: :type, meta: %{syn_name: name}} = type, index)
       when is_binary(name) do
    case Syn.Index.public_type_name(index, name) do
      {:ok, public_name} when public_name != name ->
        put_equivalent_rust_name(type, public_name)

      _missing_or_same ->
        type
    end
  end

  defp annotate_public_alias_type(%Type{} = type, _index), do: type
  defp annotate_public_alias_type(nil, _index), do: nil

  defp put_equivalent_rust_name(%Type{} = type, name) do
    equivalents =
      type.meta
      |> Map.get(:equivalent_rust_names, [])
      |> List.wrap()
      |> Kernel.++([name])
      |> Enum.uniq()

    %{type | meta: Map.put(type.meta, :equivalent_rust_names, equivalents)}
  end

  defp cached_callables(key, fun) do
    cache_key = {__MODULE__, :callables, key}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        single_flight(cache_key, fn -> fill_callables_cache(cache_key, fun) end)

      callables ->
        callables
    end
  end

  defp fill_callables_cache(cache_key, fun) do
    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        callables = fun.()
        :persistent_term.put(cache_key, callables)
        callables

      callables ->
        callables
    end
  end

  defp single_flight(cache_key, fun) do
    :global.trans({{__MODULE__, :cache_fill, cache_key}, self()}, fun, [node()], :infinity)
  end
end
