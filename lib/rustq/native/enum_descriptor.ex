defmodule RustQ.Native.EnumDescriptor do
  @moduledoc """
  Resolved metadata for a native Rust enum.

  A descriptor combines package-scoped enum identity with parsed `RustQ.Syn.Enum`
  metadata and, when available, a web source link derived from Cargo metadata.
  """

  alias RustQ.Syn.Enum, as: SynEnum
  alias RustQ.Syn.Index

  defstruct [:package, :name, :enum, :source_url]

  @type t :: %__MODULE__{
          package: String.t() | nil,
          name: String.t(),
          enum: SynEnum.t(),
          source_url: String.t() | nil
        }

  @doc "Returns descriptor variants as `{atom_name, rust_variant}` pairs."
  @spec variants(t()) :: [{atom(), String.t()}]
  def variants(%__MODULE__{enum: %{__struct__: SynEnum, variants: variants}}) do
    Enum.map(variants, &{RustQ.Atom.identifier!(Macro.underscore(&1)), &1})
  end

  @doc "Resolves a native enum through a `RustQ.Syn.Index`."
  @spec resolve!(Index.t(), String.t(), keyword()) :: t()
  def resolve!(%Index{} = index, name, opts \\ []) when is_binary(name) do
    package_name = Keyword.get(opts, :package)
    validate_package!(index, package_name)
    enum = Index.enum!(index, name)

    %__MODULE__{
      package: package_name || package_name(index.package),
      name: name,
      enum: enum,
      source_url: source_url(index.package, enum)
    }
  end

  defp validate_package!(%Index{package: nil}, _package_name), do: :ok
  defp validate_package!(_index, nil), do: :ok

  defp validate_package!(%Index{package: %{name: name}}, name), do: :ok

  defp validate_package!(%Index{package: package}, package_name) do
    raise ArgumentError,
          "native enum package #{inspect(package_name)} does not match indexed package #{inspect(package.name)}"
  end

  defp package_name(nil), do: nil
  defp package_name(%{name: name}), do: name

  defp source_url(nil, _enum), do: nil

  defp source_url(package, %{__struct__: RustQ.Syn.Enum, source_path: path, source_line: line})
       when is_binary(path) and is_integer(line),
       do: RustQ.Cargo.source_link(package, path, line)

  defp source_url(_package, _enum), do: nil
end
