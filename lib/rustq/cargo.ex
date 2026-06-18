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

    defstruct [:name, :version, :manifest_path]

    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            manifest_path: String.t()
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
    opts
    |> package_sources!()
    |> Map.fetch!(package_name)
  rescue
    KeyError ->
      manifest_path = Keyword.get(opts, :manifest_path, "Cargo.toml")
      raise "cannot find Cargo package #{inspect(package_name)} from #{manifest_path}"
  end
end
