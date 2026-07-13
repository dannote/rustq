defmodule RustQ do
  @moduledoc """
  Rust template quasiquoting and code generation.

  RustQ renders real Rust templates from Elixir. Parse a template, bind
  placeholder identifiers/expressions, splice Rust fragments, then generate
  formatted Rust source.

  The most common entry points are:

    * `render!/3` for one-shot rendering from a string template.
    * `render_file!/2` for `.rs` template files.
    * `parse!/2`, `bind/2`, `splice/3`, and `render!/1,2` for pipeline-style generation.
    * `parse_fragment!/2` and `valid_fragment?/2` for validating explicit escapes.

  Use `RustQ.Rust.AST` builders for generated structure, the cohesive
  `RustQ.Rustler` submodules for Rustler generation, and `RustQ.Config` plus
  `mix rustq.gen` for project-level generated files.
  """

  alias RustQ.Error
  alias RustQ.Native.Nif
  alias RustQ.Template

  @type source :: iodata()

  @doc """
  Parses and validates a Rust template.

  `filename` is used only in error messages; it does not need to exist on disk.
  """
  @spec parse(source(), String.t()) :: {:ok, Template.t()} | {:error, [map()]}
  def parse(source, filename) when is_binary(filename) do
    source = IO.iodata_to_binary(source)

    case Nif.parse(source) do
      :ok -> {:ok, %Template{source: source, filename: filename}}
      {:error, errors} -> {:error, Template.normalize_errors(errors, filename)}
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
  @spec parse_file(Path.t(), keyword()) :: {:ok, Template.t()} | {:error, [map()] | File.posix()}
  def parse_file(path, opts \\ []) do
    with {:ok, source} <- File.read(path),
         {:ok, source} <- Template.expand_includes(source, path, opts) do
      parse(source, path)
    end
  end

  @doc """
  Like `parse_file/1`, but returns the template directly or raises on errors.
  """
  @spec parse_file!(Path.t(), keyword()) :: Template.t()
  def parse_file!(path, opts \\ []) do
    case parse_file(path, opts) do
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
         {:ok, source} <- Template.expand_includes(source, path, opts) do
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
      :ok -> {:ok, RustQ.Rust.fragment(kind, code)}
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
  `{:type, type}` where type is accepted by `RustQ.Rust.AST.TypeBuilder.type/1`.
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

  defp render_template(%Template{} = template, opts) do
    case Nif.render(
           template.source,
           native_bindings(template.bindings),
           native_splices(template.splices)
         ) do
      {:ok, code} ->
        code
        |> Template.with_preamble(opts)
        |> Template.maybe_rustfmt(opts, template.filename)

      {:error, errors} when is_list(errors) ->
        {:error, Template.normalize_errors(errors, template.filename)}

      {:error, message} ->
        {:error, [%{message: message, filename: template.filename}]}
    end
  end

  @doc """
  Parses and renders source, or renders an already parsed template.

  Options:

    * `:bind` - bindings passed to `bind/2`.
    * `:splice` - splice replacements passed to `splice/3`.
    * `:preamble` - optional text prepended after formatting.
  """
  @spec render(Template.t()) :: {:ok, String.t()} | {:error, [map()]}
  def render(%Template{} = template), do: render_template(template, [])

  @spec render(Template.t(), keyword()) :: {:ok, String.t()} | {:error, [map()]}
  def render(%Template{} = template, opts), do: render_template(template, opts)

  @spec render(source(), String.t()) :: {:ok, String.t()} | {:error, [map()]}
  def render(source, filename) when is_binary(filename), do: render(source, filename, [])

  @spec render(source(), String.t(), keyword()) :: {:ok, String.t()} | {:error, [map()]}
  def render(source, filename, opts) do
    with {:ok, source} <- Template.maybe_expand_includes(source, filename, opts),
         {:ok, template} <- parse(source, filename) do
      template = bind(template, Keyword.get(opts, :bind, []))

      template
      |> splice(Keyword.get(opts, :splice, []))
      |> render_template(opts)
    end
  end

  @doc "Like `render/1,2,3`, but raises on errors."
  @spec render!(Template.t()) :: String.t()
  def render!(%Template{} = template), do: render!(template, [])

  @spec render!(Template.t(), keyword()) :: String.t()
  def render!(%Template{} = template, opts) do
    case render(template, opts) do
      {:ok, code} ->
        code

      {:error, errors} ->
        raise Error, message: "RustQ render error: #{inspect(errors)}", errors: errors
    end
  end

  @spec render!(source(), String.t()) :: String.t()
  def render!(source, filename) when is_binary(filename), do: render!(source, filename, [])

  @spec render!(source(), String.t(), keyword()) :: String.t()
  def render!(source, filename, opts) do
    case render(source, filename, opts) do
      {:ok, code} ->
        code

      {:error, errors} ->
        raise Error, message: "RustQ render error: #{inspect(errors)}", errors: errors
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
    do:
      validate_binding_fragment(
        :value,
        RustQ.Rust.fragment(:expr, code),
        "fn target() { __rq_value!(); }"
      )

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

  defp native_bindings(bindings) do
    Enum.map(bindings, fn {name, value} -> {Atom.to_string(name), binding_value(value)} end)
  end

  defp binding_value(%RustQ.Rust.Fragment{} = fragment), do: RustQ.Rust.to_fragment(fragment)
  defp binding_value(%{__struct__: _module} = ast), do: RustQ.Rust.to_fragment(ast)
  defp binding_value({:literal, value}), do: RustQ.Rust.literal(value)
  defp binding_value({:expr, value}), do: IO.iodata_to_binary(value)
  defp binding_value({:type, value}), do: RustQ.Rust.render_type(value)
  defp binding_value(value) when is_atom(value), do: Atom.to_string(value)
  defp binding_value(value) when is_binary(value), do: value
  defp binding_value(value) when is_list(value), do: IO.iodata_to_binary(value)

  defp native_splices(splices) do
    Enum.map(splices, fn {name, items} ->
      {Atom.to_string(name), Enum.map(items, &RustQ.Rust.to_fragment/1)}
    end)
  end
end
