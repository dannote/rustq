defmodule RustQ.Generated do
  @moduledoc """
  File sync helpers for RustQ-generated sources.

  Most projects should use `rustq.exs` with `mix rustq.gen`. Use this module
  directly when a project already has its own Mix task and only needs RustQ's
  write/check behavior.

      RustQ.Generated.sync!(:helpers,
        path: "native/my_nif/src/generated_helpers.rs",
        build: fn -> render_helpers() end
      )

  Pass `check: true` to compare without writing, which is useful in CI.
  """
  defmodule StaleError do
    @moduledoc """
    Raised when generated files differ from the contents produced by the manifest.
    """

    defexception [:paths, command: "mix rustq.gen"]

    @impl true
    def message(%{paths: paths, command: command}) do
      paths = List.wrap(paths)

      stale =
        case paths do
          [path] -> "generated file is stale: #{path}"
          paths -> "generated files are stale:\n" <> Enum.map_join(paths, "\n", &"  - #{&1}")
        end

      "#{stale}\nRun: #{command}"
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

    targets =
      Enum.filter(targets, fn {name, _target} -> only == [] or to_string(name) in only end)

    if Keyword.get(opts, :check, false) do
      check_all!(targets, opts)
    else
      Enum.each(targets, fn {name, target} -> sync!(name, target, opts) end)
    end

    :ok
  end

  @spec sync!(atom() | String.t(), keyword(), keyword()) :: :ok
  def sync!(name, target, opts \\ []) do
    path = Keyword.fetch!(target, :path)
    contents = target |> build!() |> normalize_newlines()

    if Keyword.get(opts, :check, false) do
      check!(path, contents, command: Keyword.get(opts, :command, "mix rustq.gen"))
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

  @spec check!(Path.t(), iodata(), keyword()) :: :ok
  def check!(path, expected, opts \\ []) do
    expected = normalize_newlines(expected)
    actual = if File.exists?(path), do: File.read!(path) |> normalize_newlines(), else: nil

    if actual == expected do
      :ok
    else
      raise StaleError,
        paths: [Path.relative_to_cwd(path)],
        command: Keyword.get(opts, :command, "mix rustq.gen")
    end
  end

  defp check_all!(targets, opts) do
    stale_paths =
      targets
      |> Enum.reject(fn {name, target} ->
        path = Keyword.fetch!(target, :path)
        contents = target |> build!() |> normalize_newlines()

        if fresh?(path, contents) do
          emit(opts, "Fresh #{name}: #{Path.relative_to_cwd(path)}")
          true
        else
          false
        end
      end)
      |> Enum.map(fn {_name, target} ->
        target |> Keyword.fetch!(:path) |> Path.relative_to_cwd()
      end)

    if stale_paths != [] do
      raise StaleError,
        paths: stale_paths,
        command: Keyword.get(opts, :command, "mix rustq.gen")
    end
  end

  defp fresh?(path, expected) do
    File.exists?(path) and File.read!(path) |> normalize_newlines() == expected
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
