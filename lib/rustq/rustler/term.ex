defmodule RustQ.Rustler.Term do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Meta.Ast, as: MetaAst
  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I
  alias RustQ.Rustler.HelperSelection
  alias RustQ.Type, as: R

  require I

  @builder_names [:map_from_terms, :struct_from_terms]
  @builder_function_names %{
    map_from_terms: :make_map_from_terms,
    struct_from_terms: :make_struct_from_terms
  }

  @helper_names [
    :get,
    :is_nil,
    :opt,
    :str_val,
    :bool_val,
    :f64_val,
    :list_val,
    :type_atom,
    :type_eq,
    :type_str
  ]

  @rusty_helper_names @helper_names

  @spec make_map_from_terms(R.path(:Env, R.lifetime(:a)), R.slice({term(), term()})) ::
          R.nif_result(term())
  defrust make_map_from_terms(env, pairs) do
    keys = Vec.with_capacity(pairs.len())
    values = Vec.with_capacity(pairs.len())

    for {key, value} <- pairs.iter().copied() do
      keys.push(key)
      values.push(value)
    end

    Term.map_from_term_arrays(env, ref(keys), ref(values))
  end

  @spec make_struct_from_terms(R.path(:Env, R.lifetime(:a)), R.slice(term()), R.slice(term())) ::
          R.nif_result(term())
  defrust make_struct_from_terms(env, keys, values) do
    Term.map_from_term_arrays(env, keys, values)
  end

  @spec get(term(), R.path({:rustler, :Atom})) :: R.option(term())
  defrust get(term, key) do
    case term.map_get(key) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  @spec is_nil(term()) :: boolean()
  defrust is_nil(term) do
    if term.is_atom() do
      case term.atom_to_string() do
        {:ok, value} -> value == "nil"
        {:error, _reason} -> false
      end
    else
      false
    end
  end

  @spec opt(term(), R.path({:rustler, :Atom})) :: R.option(term())
  defrust opt(term, key) do
    case get(term, key) do
      {:some, value} ->
        if is_nil(value) do
          nil
        else
          value
        end

      :none ->
        nil
    end
  end

  @spec str_val(term(), R.path({:rustler, :Atom})) :: String.t()
  defrust str_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        case decode_as(value, String.t()) do
          {:ok, decoded} ->
            decoded

          {:error, _reason} ->
            value.atom_to_string().unwrap_or_default()
        end

      :none ->
        String.new()
    end
  end

  @spec bool_val(term(), R.path({:rustler, :Atom})) :: boolean()
  defrust bool_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        value.decode().unwrap_or_default()

      :none ->
        false
    end
  end

  @spec f64_val(term(), R.path({:rustler, :Atom})) :: R.f64()
  defrust f64_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        case decode_as(value, R.f64()) do
          {:ok, decoded} ->
            decoded

          {:error, _reason} ->
            case decode_as(value, R.i64()) do
              {:ok, decoded} -> cast(decoded, :f64)
              {:error, _reason} -> 0.0
            end
        end

      :none ->
        0.0
    end
  end

  @spec list_val(term(), R.path({:rustler, :Atom})) :: R.vec(term())
  defrust list_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        value.decode().unwrap_or_default()

      :none ->
        Vec.new()
    end
  end

  @spec type_atom(term()) :: R.option(R.path({:rustler, :Atom}))
  defrust type_atom(term) do
    case get(term, Atoms.type()) do
      {:some, value} ->
        case decode_as(value, R.path({:rustler, :Atom})) do
          {:ok, decoded} -> decoded
          {:error, _reason} -> nil
        end

      :none ->
        nil
    end
  end

  @spec type_eq(term(), R.path({:rustler, :Atom})) :: boolean()
  defrust type_eq(term, expected) do
    type_atom(term) == some(expected)
  end

  @spec type_str(term()) :: String.t()
  defrust type_str(term) do
    case get(term, Atoms.type()) do
      {:some, value} ->
        case value.atom_to_string() do
          {:ok, decoded} -> decoded
          {:error, _reason} -> String.from("<no type>")
        end

      :none ->
        String.from("<no type>")
    end
  end

  @spec builders(keyword()) :: [Rust.Fragment.t()]
  def builders(opts \\ []) do
    opts
    |> HelperSelection.names(@builder_names)
    |> Enum.map(&builder_item/1)
  end

  @spec decoder(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def decoder(name, opts) do
    lifetime = Keyword.get(opts, :lifetime, :a)
    fields = Keyword.fetch!(opts, :fields)
    function_name = Keyword.get(opts, :fn, default_decoder_name(name))
    term_arg = Keyword.get(opts, :term_arg, :term)
    term_type = Keyword.get(opts, :term_type, "Term<'#{lifetime}>")

    result = Keyword.get(opts, :result, :nif)
    result_type = result_type(name, lifetime, result)

    Rust.ast_items([
      struct_ast(name, fields, lifetime),
      decoder_ast(name, function_name, fields, term_arg, term_type, result_type, result, lifetime)
    ])
  end

  @spec helpers(keyword()) :: [Rust.Fragment.t()]
  def helpers(opts \\ []) do
    opts
    |> HelperSelection.names(@helper_names)
    |> Enum.map(&helper_item/1)
  end

  defp builder_item(name) do
    function_name = Map.fetch!(@builder_function_names, name)
    MetaAst.item(__MODULE__, function_name)
  end

  defp helper_item(name) when name in @rusty_helper_names,
    do: MetaAst.item(__MODULE__, name)

  defp struct_ast(name, fields, lifetime) do
    I.struct ident_atom(name), lifetime: lifetime do
      struct_fields(fields)
    end
  end

  defp decoder_ast(
         name,
         function_name,
         fields,
         term_arg,
         term_type,
         result_type,
         result,
         lifetime
       ) do
    %AST.Function{
      name: ident_atom(function_name),
      lifetime: lifetime,
      args: [A.arg(ident_atom(term_arg), term_type)],
      returns: Rust.type(result_type),
      body: [
        A.return_stmt(
          A.ok(A.struct(A.path(ident_atom(name)), decoder_inits(fields, term_arg, result)))
        )
      ]
    }
  end

  defp struct_fields(fields) do
    Enum.map(fields, fn {field_name, spec} ->
      I.field(field_name, Keyword.fetch!(spec, :type), vis: nil)
    end)
  end

  defp decoder_inits(fields, term_arg, result) do
    Enum.map(fields, fn {field_name, spec} ->
      spec = Keyword.put_new(spec, :field, field_name)
      {field_name, A.escape_expr(decoder_expr(spec, term_arg, result))}
    end)
  end

  defp decoder_expr(spec, term_arg, result) do
    cond do
      decode = Keyword.get(spec, :decode) ->
        decode

      Keyword.get(spec, :required, false) ->
        required_expr(spec, term_arg, result)

      Keyword.has_key?(spec, :default) ->
        "#{term_arg}.map_get(#{key!(spec)}).ok().and_then(|t| t.decode::<#{Rust.type(Keyword.fetch!(spec, :type))}>().ok()).unwrap_or(#{Keyword.fetch!(spec, :default)})"

      true ->
        "#{term_arg}.map_get(#{key!(spec)}).ok().and_then(|t| t.decode::<#{inner_option_type(Keyword.fetch!(spec, :type))}>().ok())"
    end
  end

  defp required_expr(spec, term_arg, :nif) do
    "#{term_arg}.map_get(#{key!(spec)})?.decode::<#{Rust.type(Keyword.fetch!(spec, :type))}>()?"
  end

  defp required_expr(spec, term_arg, _result) do
    field = Keyword.fetch!(spec, :field)
    type = Rust.type(Keyword.fetch!(spec, :type))
    missing = Keyword.get(spec, :missing, "Missing :#{field}")
    invalid = Keyword.get(spec, :invalid, "Invalid :#{field}")

    "#{term_arg}.map_get(#{key!(spec)}).map_err(|_| #{inspect(missing)}.to_string())?.decode::<#{type}>().map_err(|_| #{inspect(invalid)}.to_string())?"
  end

  defp key!(spec), do: Keyword.fetch!(spec, :key)

  defp inner_option_type({:option, type}), do: Rust.type(type)
  defp inner_option_type(type), do: Rust.type(type)

  defp result_type(name, lifetime, :nif), do: {:raw, "NifResult<#{name}<'#{lifetime}>>"}
  defp result_type(name, lifetime, result), do: {:raw, "#{result}<#{name}<'#{lifetime}>>"}

  defp ident_atom(value) when is_atom(value), do: value
  defp ident_atom(value) when is_binary(value), do: RustQ.Atom.identifier!(value)

  defp default_decoder_name(name), do: "decode_#{Macro.underscore(to_string(name))}"
end
