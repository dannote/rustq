defmodule RustQ.Specs do
  @moduledoc """
  Structural reflection for Elixir `@type`/`@spec` declarations.

  This module reads quoted Elixir AST. It does not compile or execute the
  source file, and it does not infer Rust semantics. Callers provide a type
  mapper when domain-specific type names should become codegen types.
  """

  @type type_mapper :: (Macro.t(), %{atom() => Macro.t()} -> term())
  @type option :: keyword()
  @type function_schema :: %{name: atom(), args: keyword(), opts: [option()]}

  @spec from_file(Path.t(), keyword()) :: [function_schema()]
  def from_file(path, opts \\ []) do
    path
    |> File.read!()
    |> Code.string_to_quoted!(file: path)
    |> from_quoted(opts)
  end

  @spec from_quoted(Macro.t(), keyword()) :: [function_schema()]
  def from_quoted(quoted, opts \\ []) do
    type_mapper = Keyword.get(opts, :type_mapper, &default_type/2)
    {types, specs, defs} = collect_declarations(quoted)

    specs
    |> Enum.filter(fn {name, spec_arg_types} ->
      Map.has_key?(defs, name) and is_list(spec_arg_types) and length(spec_arg_types) >= 2
    end)
    |> Enum.map(fn {name, spec_arg_types} ->
      def_args = Map.fetch!(defs, name)
      function_from_spec(name, def_args, spec_arg_types, types, type_mapper)
    end)
  end

  @spec expand_type(Macro.t(), %{atom() => Macro.t()}) :: Macro.t()
  def expand_type({name, _, []} = ast, types) when is_atom(name) do
    case Map.fetch(types, name) do
      {:ok, type_ast} -> expand_type(type_ast, types)
      :error -> ast
    end
  end

  def expand_type(other, _types), do: other

  defp collect_declarations({:defmodule, _meta, [_module, [do: body]]}),
    do: collect_declarations(body)

  defp collect_declarations(body) do
    body
    |> block_expressions()
    |> Enum.reduce({%{}, [], %{}}, fn
      {:@, _, [{:type, _, [{:"::", _, [{name, _, _ctx}, type_ast]}]}]}, {types, specs, defs} ->
        {Map.put(types, name, type_ast), specs, defs}

      {:@, _, [{:spec, _, [{:"::", _, [{name, _, arg_types}, _return]}]}]},
      {types, specs, defs} ->
        {types, specs ++ [{name, arg_types}], defs}

      {:def, _, [{name, _, args}, _body]}, {types, specs, defs} ->
        {types, specs, Map.put(defs, name, Enum.map(args || [], &arg_name!/1))}

      _other, acc ->
        acc
    end)
  end

  defp function_from_spec(name, def_args, spec_arg_types, types, type_mapper) do
    arg_names = def_args |> Enum.drop(1) |> Enum.drop(-1)
    arg_types = spec_arg_types |> Enum.drop(1) |> Enum.drop(-1)
    opts_type = List.last(spec_arg_types)

    %{
      name: name,
      args: Enum.zip(arg_names, Enum.map(arg_types, &type_mapper.(&1, types))),
      opts: opts_type |> expand_type(types) |> opts_from_map_type(types, type_mapper)
    }
  end

  defp arg_name!({name, _, context}) when is_atom(name) and is_atom(context), do: name

  defp arg_name!(other),
    do: raise(ArgumentError, "unsupported declaration argument #{Macro.to_string(other)}")

  defp opts_from_map_type({:%{}, _, fields}, types, type_mapper) do
    Enum.map(fields, fn {{required, _, [name]}, type_ast}
                        when required in [:required, :optional] ->
      [name: name, type: type_mapper.(type_ast, types), required: required == :required]
    end)
  end

  defp opts_from_map_type(other, _types, _type_mapper),
    do: raise(ArgumentError, "expected map option type, got #{Macro.to_string(other)}")

  defp default_type(ast, types), do: ast |> expand_type(types) |> Macro.to_string()

  defp block_expressions({:__block__, _, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]
end
