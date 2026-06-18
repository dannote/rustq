defmodule RustQ.NativeDescriptor do
  @moduledoc """
  Resolved metadata for a `RustQ.NativeRef`.

  A descriptor combines a native reference with parsed `RustQ.Syn` method
  metadata and, when available, a web source link derived from Cargo metadata.
  """

  defstruct [:ref, :method, :source_url]

  @type t :: %__MODULE__{
          ref: RustQ.NativeRef.t(),
          method: RustQ.Syn.Method.t(),
          source_url: String.t() | nil
        }

  @doc "Resolves a native method reference through a `RustQ.Syn.Index`."
  @spec resolve!(RustQ.Syn.Index.t(), RustQ.NativeRef.t()) :: t()
  def resolve!(%RustQ.Syn.Index{} = index, %RustQ.NativeRef{} = ref) do
    validate_package!(index, ref)

    method = RustQ.Syn.Index.method!(index, ref.target, ref.member)

    %__MODULE__{
      ref: ref,
      method: method,
      source_url: source_url(index.package, method)
    }
  end

  defp validate_package!(%RustQ.Syn.Index{package: nil}, _ref), do: :ok
  defp validate_package!(_index, %RustQ.NativeRef{package: nil}), do: :ok

  defp validate_package!(%RustQ.Syn.Index{package: %{name: name}}, %RustQ.NativeRef{package: name}),
       do: :ok

  defp validate_package!(%RustQ.Syn.Index{package: package}, %RustQ.NativeRef{} = ref) do
    raise ArgumentError,
          "native ref package #{inspect(ref.package)} does not match indexed package #{inspect(package.name)}"
  end

  defp source_url(nil, _method), do: nil

  defp source_url(package, %RustQ.Syn.Method{source_path: path, source_line: line})
       when is_binary(path) and is_integer(line),
       do: RustQ.Cargo.source_link(package, path, line)

  defp source_url(_package, _method), do: nil
end
