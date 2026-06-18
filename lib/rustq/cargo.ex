defmodule RustQ.Cargo do
  @moduledoc """
  Helpers for discovering Rust package metadata through Cargo.

  This module wraps `cargo metadata` so generators can find source roots for
  registry, git, and path dependencies without assuming Cargo's on-disk cache
  layout.
  """

  defmodule Package do
    @moduledoc "Package entry from `cargo metadata`."

    use JSONCodec, fast_path: :json

    defstruct [:name, :version, :manifest_path, :source, :repository]

    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            manifest_path: String.t(),
            source: String.t() | nil,
            repository: String.t() | nil
          }
  end

  defmodule Metadata do
    @moduledoc "Decoded subset of `cargo metadata` used by RustQ."

    use JSONCodec, fast_path: :json

    defstruct packages: []

    @type t :: %__MODULE__{packages: [RustQ.Cargo.Package.t()]}
  end

  @doc """
  Returns decoded `cargo metadata` for a manifest.

  Options:

    * `:manifest_path` - path to `Cargo.toml`. Defaults to `"Cargo.toml"`.

  """
  @spec metadata!(keyword()) :: Metadata.t()
  def metadata!(opts \\ []) do
    manifest_path = Keyword.get(opts, :manifest_path, "Cargo.toml")

    args = [
      "metadata",
      "--format-version=1",
      "--manifest-path",
      manifest_path
    ]

    case System.cmd("cargo", args) do
      {json, 0} ->
        Metadata.decode!(json)

      {output, status} ->
        raise "cargo metadata failed with status #{status}: #{output}"
    end
  end

  @doc """
  Returns package metadata by name.

  Raises if the package is not present in `cargo metadata` output.
  """
  @spec package!(String.t(), keyword()) :: Package.t()
  def package!(package_name, opts \\ []) when is_binary(package_name) do
    opts
    |> metadata!()
    |> Map.fetch!(:packages)
    |> Enum.find(&(&1.name == package_name))
    |> case do
      %Package{} = package -> package
      nil -> raise_missing_package!(package_name, opts)
    end
  end

  @doc """
  Returns all package source roots from Cargo metadata.

  The returned map keys are package names and values are source directories
  derived from each package's `manifest_path`.
  """
  @spec package_sources!(keyword()) :: %{String.t() => Path.t()}
  def package_sources!(opts \\ []) do
    opts
    |> metadata!()
    |> Map.fetch!(:packages)
    |> Map.new(fn %Package{name: name, manifest_path: manifest_path} ->
      {name, Path.dirname(manifest_path)}
    end)
  end

  @doc """
  Returns the source root for a package by name.

  Raises if the package is not present in `cargo metadata` output.
  """
  @spec package_source!(String.t(), keyword()) :: Path.t()
  def package_source!(package_name, opts \\ []) when is_binary(package_name) do
    package_name
    |> package!(opts)
    |> Map.fetch!(:manifest_path)
    |> Path.dirname()
  end

  @doc """
  Returns a web source link for a package source path and line.

  Registry packages currently link to docs.rs source pages. Path packages or
  paths outside the package root return `nil`.
  """
  @spec source_link(Package.t(), Path.t(), pos_integer()) :: String.t() | nil
  def source_link(%Package{} = package, source_path, line)
      when is_binary(source_path) and is_integer(line) do
    with true <- registry_package?(package),
         root = Path.dirname(package.manifest_path),
         relative when not is_nil(relative) <- relative_source_path(root, source_path) do
      "https://docs.rs/crate/#{package.name}/#{package.version}/source/#{relative}#L#{line}"
    else
      _ -> nil
    end
  end

  @doc "Returns a web source link for a package by name, path, and line."
  @spec source_link(String.t(), Path.t(), pos_integer(), keyword()) :: String.t() | nil
  def source_link(package_name, source_path, line, opts \\ []) do
    package_name
    |> package!(opts)
    |> source_link(source_path, line)
  end

  defp registry_package?(%Package{source: "registry+" <> _}), do: true
  defp registry_package?(%Package{source: nil}), do: false
  defp registry_package?(%Package{}), do: false

  defp relative_source_path(root, source_path) do
    root = Path.expand(root)
    source_path = Path.expand(source_path)

    if String.starts_with?(source_path, root <> "/") do
      Path.relative_to(source_path, root)
    end
  end

  defp raise_missing_package!(package_name, opts) do
    manifest_path = Keyword.get(opts, :manifest_path, "Cargo.toml")
    raise "cannot find Cargo package #{inspect(package_name)} from #{manifest_path}"
  end
end
