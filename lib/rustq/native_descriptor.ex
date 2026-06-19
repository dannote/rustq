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

  @type expected_arg ::
          :self_ref
          | {:ref, String.t()}
          | {:impl_trait, String.t(), [String.t()]}
          | {:path, String.t()}
          | :any
  @type expected_return :: {:ref, String.t()} | {:path, String.t()} | :none | :any

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

  @doc "Resolves a native method reference and validates its argument/return shape."
  @spec resolve!(RustQ.Syn.Index.t(), RustQ.NativeRef.t(), keyword()) :: t()
  def resolve!(%RustQ.Syn.Index{} = index, %RustQ.NativeRef{} = ref, opts) when is_list(opts) do
    index
    |> resolve!(ref)
    |> assert_shape!(opts)
  end

  @doc "Validates a descriptor's method argument/return shape."
  @spec assert_shape!(t(), keyword()) :: t()
  def assert_shape!(%__MODULE__{} = descriptor, opts) when is_list(opts) do
    method = descriptor.method
    expected_args = Keyword.get(opts, :args, :any)
    expected_returns = Keyword.get(opts, :returns, :any)

    assert_args_match!(descriptor, expected_args)

    unless return_matches?(method.returns_ast, expected_returns) do
      raise "unexpected native return for #{RustQ.NativeRef.format(descriptor.ref)}: #{inspect(method.returns_ast)}"
    end

    descriptor
  end

  defp assert_args_match!(_descriptor, :any), do: :ok

  defp assert_args_match!(%__MODULE__{} = descriptor, expected_args) do
    actual = Enum.map(descriptor.method.args, & &1.type_ast)

    unless length(actual) == length(expected_args) and
             Enum.zip(actual, expected_args)
             |> Enum.all?(fn {type, expected} -> type_matches?(type, expected) end) do
      raise "unexpected native args for #{RustQ.NativeRef.format(descriptor.ref)}: #{inspect(descriptor.method.args)}"
    end
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

  defp type_matches?(_type, :any), do: true
  defp type_matches?(%RustQ.Syn.Type.Ref{inner: %RustQ.Syn.Type.Self{}}, :self_ref), do: true
  defp type_matches?(%RustQ.Syn.Type.Ref{inner: %RustQ.Syn.Type.Self{}}, {:ref, "Self"}), do: true
  defp type_matches?(type, {:ref, name}), do: RustQ.Syn.Type.ref_to?(type, name)

  defp type_matches?(type, {:impl_trait, trait, args}),
    do: RustQ.Syn.Type.impl_trait?(type, trait, args)

  defp type_matches?(type, {:path, name}), do: RustQ.Syn.Type.path?(type, name)
  defp type_matches?(_type, _expected), do: false

  defp return_matches?(_type, :any), do: true
  defp return_matches?(nil, :none), do: true
  defp return_matches?(type, {:ref, name}), do: type_matches?(type, {:ref, name})
  defp return_matches?(type, {:path, name}), do: type_matches?(type, {:path, name})
  defp return_matches?(_type, _expected), do: false
end
