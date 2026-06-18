defmodule RustQ.Syn.Index do
  @moduledoc """
  In-memory index of Rust source metadata parsed by `RustQ.Syn`.

  Use an index when a generator needs to query many Rust files without keeping
  project-specific source maps. The index stores parsed files by path and offers
  lookup helpers for impl blocks and methods by target type.
  """

  defstruct files: %{}

  @type t :: %__MODULE__{files: %{Path.t() => RustQ.Syn.File.t()}}

  @doc "Builds an index from Rust source file paths."
  @spec from_paths([Path.t()]) :: t()
  def from_paths(paths) when is_list(paths) do
    files =
      paths
      |> Enum.uniq()
      |> Map.new(fn path -> {path, RustQ.Syn.parse_file!(path)} end)

    %__MODULE__{files: files}
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

  defp target_matches?(%RustQ.Syn.Type.Path{name: name}, target), do: name == target

  defp target_matches?(%RustQ.Syn.Type.Raw{code: code}, target), do: code == target
  defp target_matches?(_type, _target), do: false
end
