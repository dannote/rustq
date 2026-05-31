defmodule RustQ do
  @moduledoc """
  Rust templates and quasiquoting for Elixir.

  RustQ follows the same pipeline shape as `oxc_ex`: parse a real source
  template, bind placeholder identifiers or expressions, splice generated
  fragments, then codegen formatted source.
  """

  alias RustQ.Template

  defmodule Error do
    defexception [:message, :errors]
  end

  @type source :: iodata()

  @doc """
  Parses and validates a Rust template.
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
  """
  @spec from_file(Path.t()) :: {:ok, Template.t()} | {:error, [map()] | File.posix()}
  def from_file(path) do
    case File.read(path) do
      {:ok, source} -> parse(source, path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Like `from_file/1`, but returns the template directly or raises on errors.
  """
  @spec from_file!(Path.t()) :: Template.t()
  def from_file!(path) do
    path
    |> File.read!()
    |> parse!(path)
  end

  @doc """
  Renders a Rust template file.
  """
  @spec render_file(Path.t(), keyword()) :: {:ok, String.t()} | {:error, [map()] | File.posix()}
  def render_file(path, opts \\ []) do
    with {:ok, source} <- File.read(path) do
      render(source, path, opts)
    end
  end

  @doc """
  Like `render_file/2`, but raises on errors.
  """
  @spec render_file!(Path.t(), keyword()) :: String.t()
  def render_file!(path, opts \\ []) do
    path
    |> File.read!()
    |> render!(path, opts)
  end

  @doc """
  Parses and validates a Rust fragment for a specific context.
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

  Supported placeholder forms:

    * `__Name` for identifier/type-path replacement
    * `__expr_name!()` for expression replacement
    * `__type_name!()` for type replacement

  Values may be strings, atoms, `{:literal, value}`, `{:expr, code}`, or
  `{:type, type}` where type uses `RustQ.Rust.type/1` syntax.
  """
  @spec bind(Template.t(), keyword()) :: Template.t()
  def bind(%Template{} = template, bindings) when is_list(bindings) do
    %{template | bindings: Keyword.merge(template.bindings, bindings)}
  end

  @doc """
  Splices fragments at `__splice_name!()` placeholders.
  """
  @spec splice(Template.t(), atom(), term() | [term()]) :: Template.t()
  def splice(%Template{} = template, name, replacement) when is_atom(name) do
    %{template | splices: Keyword.put(template.splices, name, List.wrap(replacement))}
  end

  @doc """
  Generates formatted Rust source from a parsed template.
  """
  @spec codegen(Template.t()) :: {:ok, String.t()} | {:error, [map()]}
  def codegen(%Template{} = template) do
    case RustQ.Native.render(
           template.source,
           native_bindings(template.bindings),
           native_splices(template.splices)
         ) do
      {:ok, code} ->
        {:ok, code}

      {:error, errors} when is_list(errors) ->
        {:error, normalize_errors(errors, template.filename)}

      {:error, message} ->
        {:error, [%{message: message, filename: template.filename}]}
    end
  end

  @doc """
  Like `codegen/1`, but raises on errors.
  """
  @spec codegen!(Template.t()) :: String.t()
  def codegen!(%Template{} = template) do
    case codegen(template) do
      {:ok, code} ->
        code

      {:error, errors} ->
        raise Error, message: "RustQ codegen error: #{inspect(errors)}", errors: errors
    end
  end

  @doc """
  Convenience wrapper around `parse!/2`, `bind/2`, `splice/3`, and `codegen/1`.
  """
  @spec render(source(), String.t(), keyword()) :: {:ok, String.t()} | {:error, [map()]}
  def render(source, filename, opts \\ []) do
    with {:ok, template} <- parse(source, filename) do
      template = bind(template, Keyword.get(opts, :bind, []))

      opts
      |> Keyword.get(:splice, [])
      |> Enum.reduce(template, fn {name, replacement}, acc -> splice(acc, name, replacement) end)
      |> codegen()
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

  defp validate_fragment(:item, code),
    do: validate_splice_fragment(:items, code, "__splice_items!();")

  defp validate_fragment(:impl_item, code) do
    validate_splice_fragment(:items, code, "impl Target { __splice_items!(); }")
  end

  defp validate_fragment(:field, code) do
    validate_splice_fragment(:fields, code, "struct Target { __splice_fields: (), }")
  end

  defp validate_fragment(:stmt, code),
    do: validate_splice_fragment(:body, code, "fn target() { __splice_body!(); }")

  defp validate_fragment(:arg, code),
    do: validate_splice_fragment(:args, code, "fn target(__splice_args: ()) {}")

  defp validate_fragment(:arm, code) do
    validate_splice_fragment(
      :arms,
      code,
      "fn target(value: Option<i32>) { match value { __splice_arms => unreachable!(), } }"
    )
  end

  defp validate_fragment(:expr, code),
    do:
      validate_binding_fragment(:value, RustQ.Rust.expr(code), "fn target() { __expr_value!(); }")

  defp validate_fragment(:type, code),
    do: validate_binding_fragment(:value, {:type, {:raw, code}}, "type Target = __type_value!();")

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
