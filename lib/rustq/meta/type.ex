defmodule RustQ.Meta.Type do
  @moduledoc false

  alias RustQ.Rust.AST

  defstruct [:kind, :rust, :ast, meta: %{}]

  @type t :: %__MODULE__{kind: atom(), rust: String.t(), ast: term(), meta: map()}

  @spec from_spec_ast(Macro.t(), map()) :: t()
  def from_spec_ast(ast, aliases \\ %{}), do: parse(ast, aliases)

  @spec type_aliases([term()]) :: map()
  def type_aliases(types) do
    types
    |> List.wrap()
    |> Enum.reverse()
    |> Map.new(fn {:type, {:"::", _, [{name, _, args}, ast]}, _location} ->
      arity = args |> List.wrap() |> length()
      rust_name = name |> Atom.to_string() |> Macro.camelize()
      {{name, arity}, parse_type_alias(name, ast, rust_name)}
    end)
  end

  defp parse_type_alias(name, ast, rust_name) do
    cond do
      atom_union?(ast) ->
        type(:enum, path(rust_name), %{elixir_name: name, variants: union_members(ast)})

      option_union?(ast) ->
        [_nil, inner] = option_members(ast)
        inner_type = parse(inner, %{})

        type(:option, %AST.TypeOption{inner: inner_type.ast}, %{
          elixir_name: name,
          inner: inner_type
        })

      result_union?(ast) ->
        {ok, error} = result_members(ast)
        ok_type = parse(ok, %{})
        error_type = parse(error, %{})

        type(:result, %AST.TypeResult{ok: ok_type.ast, error: error_type.ast}, %{
          elixir_name: name,
          ok: ok_type,
          error: error_type
        })

      map_type?(ast) ->
        fields = map_fields(ast)

        lifetimes =
          if Enum.any?(fields, fn {_name, type, _presence} ->
               String.contains?(type.rust, "'a")
             end), do: [:a], else: []

        type(:struct, %AST.TypePath{parts: [rust_name], lifetimes: lifetimes}, %{
          elixir_name: name,
          rust_name: rust_name,
          fields: fields
        })

      true ->
        type(:alias, path(rust_name), %{elixir_name: name, ast: ast})
    end
  end

  defp parse({{:., _, [module, function]}, _, args}, aliases),
    do: parse_remote(module, function, args, aliases)

  defp parse({name, _, args}, aliases) when is_atom(name) and is_list(args) do
    case Map.get(aliases, {name, length(args)}) do
      nil -> parse_local_type(name, args, aliases)
      alias_type -> alias_type
    end
  end

  defp parse({:|, _, _args} = union, aliases) do
    cond do
      option_union?(union) ->
        [_nil, inner] = option_members(union)
        inner_type = parse(inner, aliases)
        type(:option, %AST.TypeOption{inner: inner_type.ast})

      result_union?(union) ->
        {ok, error} = result_members(union)
        ok_type = parse(ok, aliases)
        error_type = parse(error, aliases)
        type(:result, %AST.TypeResult{ok: ok_type.ast, error: error_type.ast})

      atom_union?(union) ->
        type(:enum, path(:Atom))

      true ->
        type(:type, path(:Term))
    end
  end

  defp parse({:__aliases__, _, parts}, _aliases), do: type(:type, %AST.TypePath{parts: parts})
  defp parse(atom, _aliases) when is_atom(atom), do: type(:type, path(atom))

  defp parse_remote(module, function, args, aliases) do
    if type_module?(module),
      do: parse_rust_type(function, args, aliases),
      else: parse_external_type(module, function, args, aliases)
  end

  defp type_module?({:__aliases__, _, [:R]}), do: true
  defp type_module?({:__aliases__, _, [:RustType]}), do: true
  defp type_module?({:__aliases__, _, [:RustQ, :Type]}), do: true
  defp type_module?(_module), do: false

  defp parse_local_type(:atom, [], _aliases), do: type(:atom, path(:Atom))
  defp parse_local_type(:boolean, [], _aliases), do: type(:bool, path(:bool))
  defp parse_local_type(:integer, [], _aliases), do: type(:i64, path(:i64))
  defp parse_local_type(:float, [], _aliases), do: type(:f64, path(:f64))

  defp parse_local_type(:term, [], _aliases),
    do: type(:term, %AST.TypePath{parts: [:Term], lifetimes: [:a]})

  defp parse_local_type(:binary, [], _aliases), do: type(:type, %AST.TypeVec{inner: path(:u8)})
  defp parse_local_type(name, args, aliases), do: parse_rust_type(name, args, aliases)

  defp parse_rust_type(:atom, [], _aliases), do: type(:atom, path(:Atom))
  defp parse_rust_type(:bool, [], _aliases), do: type(:bool, path(:bool))
  defp parse_rust_type(:f32, [], _aliases), do: type(:f32, path(:f32))
  defp parse_rust_type(:f64, [], _aliases), do: type(:f64, path(:f64))
  defp parse_rust_type(:i64, [], _aliases), do: type(:i64, path(:i64))

  defp parse_rust_type(:term, [], _aliases),
    do: type(:term, %AST.TypePath{parts: [:Term], lifetimes: [:a]})

  defp parse_rust_type(:u8, [], _aliases), do: type(:u8, path(:u8))
  defp parse_rust_type(:u32, [], _aliases), do: type(:u32, path(:u32))
  defp parse_rust_type(:unit, [], _aliases), do: type(:unit, %AST.TypeUnit{})

  defp parse_rust_type(:ref, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:ref, %AST.TypeRef{inner: inner.ast})
  end

  defp parse_rust_type(:mut_ref, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:mut_ref, %AST.TypeRef{inner: inner.ast, mutable: true})
  end

  defp parse_rust_type(:option, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:option, %AST.TypeOption{inner: inner.ast})
  end

  defp parse_rust_type(:vec, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:vec, %AST.TypeVec{inner: inner.ast})
  end

  defp parse_rust_type(:result, [ok, error], aliases) do
    ok = parse(ok, aliases)
    error = parse(error, aliases)
    type(:result, %AST.TypeResult{ok: ok.ast, error: error.ast})
  end

  defp parse_rust_type(:nif_result, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:nif_result, %AST.TypeNifResult{inner: inner.ast})
  end

  defp parse_rust_type(function, args, aliases) do
    type(:type, %AST.TypePath{
      parts: ["#{function}<#{Enum.map_join(args, ", ", &parse(&1, aliases).rust)}>"]
    })
  end

  defp parse_external_type({:__aliases__, _, parts}, :t, [], _aliases),
    do: type(:type, path(List.last(parts)))

  defp parse_external_type({:__aliases__, _, parts}, function, args, aliases) do
    type =
      case args do
        [] ->
          %AST.TypePath{parts: parts ++ [function]}

        args ->
          %AST.TypePath{
            parts: [
              Enum.map_join(parts ++ [function], "::", &to_string/1) <>
                "<#{Enum.map_join(args, ", ", &parse(&1, aliases).rust)}>"
            ]
          }
      end

    type(:type, type)
  end

  defp parse_external_type(_module, function, _args, _aliases), do: type(:type, path(function))

  defp map_type?({:%{}, _, fields}) when is_list(fields), do: true
  defp map_type?(_ast), do: false

  defp map_fields({:%{}, _, fields}) do
    Enum.map(fields, fn
      {{:required, _, [name]}, ast} -> {name, parse(ast, %{}), :required}
      {{:optional, _, [name]}, ast} -> {name, parse(ast, %{}), :optional}
    end)
  end

  defp union_members({:|, _, [left, right]}), do: union_members(left) ++ union_members(right)
  defp union_members(other), do: [other]

  defp atom_union?(ast), do: ast |> union_members() |> Enum.all?(&is_atom/1)

  defp option_union?(ast),
    do:
      (
        members = union_members(ast)
        nil in members and length(members) == 2
      )

  defp option_members(ast),
    do:
      (
        members = union_members(ast)
        [nil, Enum.find(members, &(&1 != nil))]
      )

  defp result_union?(ast) do
    members = union_members(ast)

    length(members) == 2 and Enum.any?(members, &match?({:ok, _}, &1)) and
      Enum.any?(members, &match?({:error, _}, &1))
  end

  defp result_members(ast) do
    members = union_members(ast)
    {:ok, ok} = Enum.find(members, &match?({:ok, _}, &1))
    {:error, error} = Enum.find(members, &match?({:error, _}, &1))
    {ok, error}
  end

  defp path(part), do: %AST.TypePath{parts: [part]}

  defp type(kind, ast, meta \\ %{}) do
    %__MODULE__{
      kind: kind,
      ast: ast,
      rust: ast |> AST.render_type() |> IO.iodata_to_binary(),
      meta: meta
    }
  end
end
