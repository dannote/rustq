defmodule RustQ do
  @moduledoc """
  Rust template quasiquoting and code generation.

  RustQ renders real Rust templates from Elixir. Parse a template, bind
  placeholder identifiers/expressions, splice Rust fragments, then generate
  formatted Rust source.

  The most common entry points are:

    * `render!/3` for one-shot rendering from a string template.
    * `render_file!/2` for `.rs` template files.
    * `parse!/2`, `bind/2`, `splice/3`, and `codegen!/2` for pipeline-style codegen.
    * `parse_fragment!/2` and `valid_fragment?/2` for validating generated snippets.

  Use `RustQ.Rust` for Rust fragment builders, `RustQ.Rustler` for Rustler code
  generators, and `RustQ.Config` plus `mix rustq.gen` for project-level generated
  files.
  """

  alias RustQ.Template

  defmodule Error do
    defexception [:message, :errors]
  end

  @type source :: iodata()

  @doc """
  Parses and validates a Rust template.

  `filename` is used only in error messages; it does not need to exist on disk.
  """
  @spec parse(source(), String.t()) :: {:ok, Template.t()} | {:error, [map()]}
  def parse(source, filename) when is_binary(filename) do
    source = IO.iodata_to_binary(source)

    case RustQ.Native.parse(source) do
      :ok -> {:ok, %Template{source: source, filename: filename}}
      {:error, errors} -> {:error, normalize_errors(errors, filename)}
    end
  end

  @doc """
  Like `parse/2`, but returns the template directly or raises on errors.
  """
  @spec parse!(source(), String.t()) :: Template.t()
  def parse!(source, filename) when is_binary(filename) do
    case parse(source, filename) do
      {:ok, template} ->
        template

      {:error, errors} ->
        raise Error, message: "RustQ parse error: #{inspect(errors)}", errors: errors
    end
  end

  @doc """
  Returns true when source is a valid Rust template.
  """
  @spec valid?(source(), String.t()) :: boolean()
  def valid?(source, filename) when is_binary(filename) do
    match?({:ok, _template}, parse(source, filename))
  end

  @doc """
  Reads and parses a Rust template file.

  Template files may include other Rust template files with
  `__rq_include!("relative/path.rs");`. Includes are expanded before Rust
  parsing and are resolved relative to the including file by default. Pass
  `:include_dir` to override the root directory for the initial file.
  """
  @spec from_file(Path.t(), keyword()) :: {:ok, Template.t()} | {:error, [map()] | File.posix()}
  def from_file(path, opts \\ []) do
    with {:ok, source} <- File.read(path),
         {:ok, source} <- expand_includes(source, path, opts) do
      parse(source, path)
    end
  end

  @doc """
  Like `from_file/1`, but returns the template directly or raises on errors.
  """
  @spec from_file!(Path.t(), keyword()) :: Template.t()
  def from_file!(path, opts \\ []) do
    case from_file(path, opts) do
      {:ok, template} ->
        template

      {:error, errors} when is_list(errors) ->
        raise Error, message: "RustQ file parse error: #{inspect(errors)}", errors: errors

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  @doc """
  Renders a Rust template file.

  Accepts the same options as `render/3`.
  """
  @spec render_file(Path.t(), keyword()) :: {:ok, String.t()} | {:error, [map()] | File.posix()}
  def render_file(path, opts \\ []) do
    with {:ok, source} <- File.read(path),
         {:ok, source} <- expand_includes(source, path, opts) do
      render(source, path, opts)
    end
  end

  @doc """
  Like `render_file/2`, but raises on errors.
  """
  @spec render_file!(Path.t(), keyword()) :: String.t()
  def render_file!(path, opts \\ []) do
    case render_file(path, opts) do
      {:ok, code} ->
        code

      {:error, errors} when is_list(errors) ->
        raise Error, message: "RustQ render file error: #{inspect(errors)}", errors: errors

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  @doc """
  Parses and validates a Rust fragment for a specific context.

  Supported contexts are `:item`, `:impl_item`, `:field`, `:stmt`, `:arg`,
  `:arm`, `:expr`, and `:type`.
  """
  @spec parse_fragment(atom(), term()) :: {:ok, RustQ.Rust.Fragment.t()} | {:error, [map()]}
  def parse_fragment(kind, fragment) when is_atom(kind) do
    code = RustQ.Rust.to_fragment(fragment)

    case validate_fragment(kind, code) do
      :ok -> {:ok, %RustQ.Rust.Fragment{kind: kind, code: code}}
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  Like `parse_fragment/2`, but returns the fragment directly or raises on errors.
  """
  @spec parse_fragment!(atom(), term()) :: RustQ.Rust.Fragment.t()
  def parse_fragment!(kind, fragment) do
    case parse_fragment(kind, fragment) do
      {:ok, fragment} ->
        fragment

      {:error, errors} ->
        raise Error, message: "RustQ fragment parse error: #{inspect(errors)}", errors: errors
    end
  end

  @doc """
  Returns true when a Rust fragment is valid for the given context.
  """
  @spec valid_fragment?(atom(), term()) :: boolean()
  def valid_fragment?(kind, fragment),
    do: match?({:ok, _fragment}, parse_fragment(kind, fragment))

  @doc """
  Binds Rust placeholders in a parsed template.

  RustQ placeholders use the `__rq_` prefix. Use `__rq_Name` where Rust expects
  an identifier/type/lifetime, and `__rq_name!()` where Rust expects an
  expression or type macro.

  Values may be strings, atoms, `{:literal, value}`, `{:expr, code}`, or
  `{:type, type}` where type uses `RustQ.Rust.type/1` syntax.
  """
  @spec bind(Template.t(), keyword()) :: Template.t()
  def bind(%Template{} = template, bindings) when is_list(bindings) do
    %{template | bindings: Keyword.merge(template.bindings, bindings)}
  end

  @doc """
  Splices fragments into a parsed template.

  The splice name matches placeholders such as `__rq_items!();`,
  `__rq_fields: (),`, or `__rq_arms => unreachable!(),`.
  """
  @spec splice(Template.t(), atom(), term() | [term()]) :: Template.t()
  def splice(%Template{} = template, name, replacement) when is_atom(name) do
    %{template | splices: Keyword.put(template.splices, name, List.wrap(replacement))}
  end

  @doc """
  Splices a keyword/map/nested list of splice replacements.

  Duplicate names are concatenated, which allows independent generators to
  contribute fragments to the same splice point.
  """
  @spec splice(Template.t(), RustQ.Splice.source()) :: Template.t()
  def splice(%Template{} = template, splices) do
    %{template | splices: RustQ.Splice.merge([template.splices, splices])}
  end

  @doc """
  Generates formatted Rust source from a parsed template.
  """
  @spec codegen(Template.t(), keyword()) :: {:ok, String.t()} | {:error, [map()]}
  def codegen(%Template{} = template, opts \\ []) do
    case RustQ.Native.render(
           template.source,
           native_bindings(template.bindings),
           native_splices(template.splices)
         ) do
      {:ok, code} ->
        {:ok, with_preamble(code, opts)}

      {:error, errors} when is_list(errors) ->
        {:error, normalize_errors(errors, template.filename)}

      {:error, message} ->
        {:error, [%{message: message, filename: template.filename}]}
    end
  end

  @doc """
  Like `codegen/2`, but raises on errors.
  """
  @spec codegen!(Template.t(), keyword()) :: String.t()
  def codegen!(%Template{} = template, opts \\ []) do
    case codegen(template, opts) do
      {:ok, code} ->
        code

      {:error, errors} ->
        raise Error, message: "RustQ codegen error: #{inspect(errors)}", errors: errors
    end
  end

  @doc """
  Convenience wrapper around `parse/2`, `bind/2`, `splice/3`, and `codegen/2`.

  Options:

    * `:bind` - bindings passed to `bind/2`.
    * `:splice` - splice replacements passed to `splice/3`.
    * `:preamble` - optional text prepended after formatting.
  """
  @spec render(source(), String.t(), keyword()) :: {:ok, String.t()} | {:error, [map()]}
  def render(source, filename, opts \\ []) do
    with {:ok, source} <- maybe_expand_includes(source, filename, opts),
         {:ok, template} <- parse(source, filename) do
      template = bind(template, Keyword.get(opts, :bind, []))

      template
      |> splice(Keyword.get(opts, :splice, []))
      |> codegen(opts)
    end
  end

  @doc """
  Like `render/3`, but raises on errors.
  """
  @spec render!(source(), String.t(), keyword()) :: String.t()
  def render!(source, filename, opts \\ []) do
    case render(source, filename, opts) do
      {:ok, code} ->
        code

      {:error, errors} ->
        raise Error, message: "RustQ render error: #{inspect(errors)}", errors: errors
    end
  end

  defp maybe_expand_includes(source, filename, opts) do
    if Keyword.has_key?(opts, :include_dir) do
      expand_includes(source, filename, opts)
    else
      {:ok, IO.iodata_to_binary(source)}
    end
  end

  defp expand_includes(source, filename, opts) do
    include_dir = Keyword.get(opts, :include_dir, Path.dirname(filename))

    source
    |> IO.iodata_to_binary()
    |> expand_includes_from(filename, include_dir, MapSet.new([Path.expand(filename)]))
  end

  @include_pattern ~r/__rq_include!\(\s*"([^"]+)"\s*\)\s*;/

  defp expand_includes_from(source, filename, include_dir, stack) do
    case Regex.run(@include_pattern, source, return: :index) do
      nil ->
        {:ok, source}

      [{start, length}, {_path_start, _path_length}] ->
        expand_next_include(source, filename, include_dir, stack, start, length)
    end
  end

  defp expand_next_include(source, filename, include_dir, stack, start, length) do
    [_matched, relative_path] = Regex.run(@include_pattern, binary_part(source, start, length))
    include_path = Path.expand(relative_path, include_dir)

    if MapSet.member?(stack, include_path) do
      include_error(filename, "cyclic RustQ include: #{include_path}")
    else
      replace_include(source, filename, include_dir, stack, start, length, include_path)
    end
  end

  defp replace_include(source, filename, include_dir, stack, start, length, include_path) do
    with {:ok, included} <- read_include(include_path, filename),
         {:ok, expanded} <-
           expand_includes_from(
             included,
             include_path,
             Path.dirname(include_path),
             MapSet.put(stack, include_path)
           ) do
      source =
        binary_part(source, 0, start) <>
          expanded <>
          binary_part(source, start + length, byte_size(source) - start - length)

      expand_includes_from(source, filename, include_dir, stack)
    end
  end

  defp read_include(path, filename) do
    case File.read(path) do
      {:ok, source} ->
        {:ok, source}

      {:error, reason} ->
        include_error(
          filename,
          "cannot read RustQ include #{path}: #{:file.format_error(reason)}"
        )
    end
  end

  defp include_error(filename, message) do
    {:error,
     [
       %{
         type: :include_error,
         context: :include,
         message: message,
         filename: filename
       }
     ]}
  end

  defp with_preamble(code, opts) do
    case Keyword.get(opts, :preamble, "") do
      nil -> code
      "" -> code
      preamble -> IO.iodata_to_binary([preamble, code])
    end
  end

  defp validate_fragment(:item, code),
    do: validate_splice_fragment(:items, code, "__rq_items!();")

  defp validate_fragment(:impl_item, code) do
    validate_splice_fragment(:items, code, "impl Target { __rq_items!(); }")
  end

  defp validate_fragment(:field, code) do
    validate_splice_fragment(:fields, code, "struct Target { __rq_fields: (), }")
  end

  defp validate_fragment(:stmt, code),
    do: validate_splice_fragment(:body, code, "fn target() { __rq_body!(); }")

  defp validate_fragment(:arg, code),
    do: validate_splice_fragment(:args, code, "fn target(__rq_args: ()) {}")

  defp validate_fragment(:arm, code) do
    validate_splice_fragment(
      :arms,
      code,
      "fn target(value: Option<i32>) { match value { __rq_arms => unreachable!(), } }"
    )
  end

  defp validate_fragment(:expr, code),
    do: validate_binding_fragment(:value, RustQ.Rust.expr(code), "fn target() { __rq_value!(); }")

  defp validate_fragment(:type, code),
    do: validate_binding_fragment(:value, {:type, {:raw, code}}, "type Target = __rq_value!();")

  defp validate_fragment(kind, _code) do
    {:error,
     [
       %{
         type: :unknown_fragment,
         context: kind,
         message: "unknown Rust fragment context",
         filename: "<fragment>"
       }
     ]}
  end

  defp validate_splice_fragment(name, code, template) do
    case render(template, "<fragment>", splice: [{name, [code]}]) do
      {:ok, _code} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  defp validate_binding_fragment(name, value, template) do
    case render(template, "<fragment>", bind: [{name, value}]) do
      {:ok, _code} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  defp normalize_errors(errors, filename) do
    Enum.map(errors, fn error ->
      error
      |> Map.update(:type, nil, &string_to_atom/1)
      |> Map.update(:context, nil, &string_to_atom/1)
      |> Map.update(:name, nil, &string_to_atom/1)
      |> Map.put(:filename, filename)
    end)
  end

  defp string_to_atom(nil), do: nil
  defp string_to_atom(value) when is_atom(value), do: value

  defp string_to_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp native_bindings(bindings) do
    Enum.map(bindings, fn {name, value} -> {Atom.to_string(name), binding_value(value)} end)
  end

  defp binding_value(%RustQ.Rust.Fragment{} = fragment), do: RustQ.Rust.to_fragment(fragment)
  defp binding_value({:literal, value}), do: RustQ.Rust.literal(value)
  defp binding_value({:expr, value}), do: IO.iodata_to_binary(value)
  defp binding_value({:type, value}), do: RustQ.Rust.type(value)
  defp binding_value(value) when is_atom(value), do: Atom.to_string(value)
  defp binding_value(value) when is_binary(value), do: value
  defp binding_value(value) when is_list(value), do: IO.iodata_to_binary(value)

  defp native_splices(splices) do
    Enum.map(splices, fn {name, items} ->
      {Atom.to_string(name), Enum.map(items, &RustQ.Rust.to_fragment/1)}
    end)
  end
end
