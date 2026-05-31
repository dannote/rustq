defmodule RustQ.Generated do
  @moduledoc """
  Shared file sync helpers for RustQ-generated sources.

  Projects can use this directly from their own Mix tasks, or declare targets in
  `rustq.exs` and use `mix rustq.gen`.
  """

  defmodule StaleError do
    @moduledoc false

    defexception [:path]

    @impl true
    def message(%{path: path}) do
      "generated file is stale: #{path}\nRun: mix rustq.gen"
    end
  end

  @type target :: {atom() | String.t(), keyword()}

  @spec load_manifest!(Path.t()) :: [target()]
  def load_manifest!(path \\ "rustq.exs") do
    unless File.exists?(path) do
      raise ArgumentError, "RustQ manifest not found: #{path}"
    end

    {manifest, _binding} = Code.eval_file(path)
    normalize_manifest!(manifest)
  end

  @spec sync_all!([target()], keyword()) :: :ok
  def sync_all!(targets, opts \\ []) do
    only = opts |> Keyword.get(:only, []) |> Enum.map(&to_string/1)

    targets
    |> Enum.filter(fn {name, _target} -> only == [] or to_string(name) in only end)
    |> Enum.each(fn {name, target} -> sync!(name, target, opts) end)

    :ok
  end

  @spec sync!(atom() | String.t(), keyword(), keyword()) :: :ok
  def sync!(name, target, opts \\ []) do
    path = Keyword.fetch!(target, :path)
    contents = target |> build!() |> normalize_newlines()

    if Keyword.get(opts, :check, false) do
      check!(path, contents)
      emit(opts, "Fresh #{name}: #{Path.relative_to_cwd(path)}")
    else
      write!(path, contents)
      emit(opts, "Generated #{name}: #{Path.relative_to_cwd(path)}")
    end

    :ok
  end

  @spec write!(Path.t(), iodata()) :: :ok
  def write!(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, normalize_newlines(contents))
  end

  @spec check!(Path.t(), iodata()) :: :ok
  def check!(path, expected) do
    expected = normalize_newlines(expected)
    actual = if File.exists?(path), do: File.read!(path) |> normalize_newlines(), else: nil

    if actual == expected do
      :ok
    else
      raise StaleError, path: Path.relative_to_cwd(path)
    end
  end

  defp normalize_manifest!(manifest) when is_list(manifest) do
    manifest
    |> Keyword.fetch!(:generated)
    |> Enum.map(fn
      {name, target} when is_list(target) -> {name, target}
      other -> raise ArgumentError, "invalid RustQ generated target: #{inspect(other)}"
    end)
  end

  defp build!(target) do
    cond do
      build = Keyword.get(target, :build) -> build.()
      Keyword.has_key?(target, :content) -> Keyword.fetch!(target, :content)
      true -> raise ArgumentError, "generated target needs :build or :content"
    end
  end

  defp normalize_newlines(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.replace("\r\n", "\n")
  end

  defp emit(opts, message) do
    case Keyword.get(opts, :shell) do
      nil -> :ok
      shell -> shell.info(message)
    end
  end
end
