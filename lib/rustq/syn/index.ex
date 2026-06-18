defmodule RustQ.Syn.Index do
  @moduledoc """
  In-memory index of Rust source metadata parsed by `RustQ.Syn`.

  Use an index when a generator needs to query many Rust files without keeping
  project-specific source maps. The index stores parsed files by path and offers
  lookup helpers for impl blocks and methods by target type.
  """

  defstruct files: %{}, package: nil

  @type t :: %__MODULE__{
          files: %{Path.t() => RustQ.Syn.File.t()},
          package: RustQ.Cargo.Package.t() | nil
        }

  @doc "Builds an index from Rust source file paths."
  @spec from_paths([Path.t()], keyword()) :: t()
  def from_paths(paths, opts \\ []) when is_list(paths) do
    files =
      paths
      |> Enum.uniq()
      |> Map.new(fn path ->
        {path, path |> RustQ.Syn.parse_file!() |> attach_source_path(path)}
      end)

    %__MODULE__{files: files, package: Keyword.get(opts, :package)}
  end

  @doc "Builds an index for all Rust sources in a Cargo package."
  @spec from_package(String.t(), keyword()) :: t()
  def from_package(package_name, opts \\ []) when is_binary(package_name) do
    package = RustQ.Cargo.package!(package_name, opts)

    package.manifest_path
    |> Path.dirname()
    |> Path.join("**/*.rs")
    |> Path.wildcard()
    |> Enum.sort()
    |> from_paths(package: package)
  end

  @doc "Returns a cached index for all Rust sources in a Cargo package."
  @spec cached_package(String.t(), keyword()) :: t()
  def cached_package(package_name, opts \\ []) when is_binary(package_name) do
    key = {__MODULE__, :package, package_name, Enum.sort(opts)}

    :persistent_term.get(key, nil) ||
      tap(from_package(package_name, opts), &:persistent_term.put(key, &1))
  end

  @doc "Clears a cached package index."
  @spec clear_cached_package(String.t(), keyword()) :: :ok
  def clear_cached_package(package_name, opts \\ []) when is_binary(package_name) do
    key = {__MODULE__, :package, package_name, Enum.sort(opts)}

    try do
      :persistent_term.erase(key)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc "Returns all indexed top-level enums."
  @spec enums(t()) :: [RustQ.Syn.Enum.t()]
  def enums(%__MODULE__{files: files}) do
    files
    |> Map.values()
    |> Enum.flat_map(&RustQ.Syn.enums/1)
  end

  @doc "Fetches an enum by name."
  @spec enum(t(), String.t()) :: {:ok, RustQ.Syn.Enum.t()} | :error
  def enum(%__MODULE__{} = index, name) when is_binary(name) do
    case Enum.find(enums(index), &(&1.name == name)) do
      nil -> :error
      enum -> {:ok, enum}
    end
  end

  @doc "Fetches an enum by name, raising if missing."
  @spec enum!(t(), String.t()) :: RustQ.Syn.Enum.t()
  def enum!(%__MODULE__{} = index, name) when is_binary(name) do
    case enum(index, name) do
      {:ok, enum} -> enum
      :error -> raise "cannot find Rust enum #{name}"
    end
  end

  @doc "Returns all indexed top-level impl blocks."
  @spec impls(t()) :: [RustQ.Syn.Impl.t()]
  def impls(%__MODULE__{files: files}) do
    files
    |> Map.values()
    |> Enum.flat_map(&RustQ.Syn.impls/1)
  end

  @doc "Returns impl blocks whose target type matches `target`."
  @spec impls(t(), String.t()) :: [RustQ.Syn.Impl.t()]
  def impls(%__MODULE__{} = index, target) when is_binary(target) do
    index
    |> impls()
    |> Enum.filter(&target_matches?(&1.target_ast, target))
  end

  @doc "Returns all methods from impl blocks matching `target`."
  @spec methods(t(), String.t()) :: [RustQ.Syn.Method.t()]
  def methods(%__MODULE__{} = index, target) when is_binary(target) do
    index
    |> impls(target)
    |> Enum.flat_map(& &1.methods)
  end

  @doc "Fetches a method from impl blocks matching `target`."
  @spec method(t(), String.t(), String.t()) :: {:ok, RustQ.Syn.Method.t()} | :error
  def method(%__MODULE__{} = index, target, name) when is_binary(target) and is_binary(name) do
    case Enum.find(methods(index, target), &(&1.name == name)) do
      nil -> :error
      method -> {:ok, method}
    end
  end

  @doc "Fetches a method from impl blocks matching `target`, raising if missing."
  @spec method!(t(), String.t(), String.t()) :: RustQ.Syn.Method.t()
  def method!(%__MODULE__{} = index, target, name) do
    case method(index, target, name) do
      {:ok, method} -> method
      :error -> raise "cannot find Rust method #{target}::#{name}"
    end
  end

  defp attach_source_path(%RustQ.Syn.File{items: items} = file, path) do
    %{file | items: Enum.map(items, &attach_item_source_path(&1, path))}
  end

  defp attach_item_source_path(%RustQ.Syn.Impl{methods: methods} = item, path) do
    %{item | source_path: path, methods: Enum.map(methods, &%{&1 | source_path: path})}
  end

  defp attach_item_source_path(item, path), do: %{item | source_path: path}

  defp target_matches?(%RustQ.Syn.Type.Path{name: name}, target), do: name == target

  defp target_matches?(%RustQ.Syn.Type.Raw{code: code}, target), do: code == target
  defp target_matches?(_type, _target), do: false
end
