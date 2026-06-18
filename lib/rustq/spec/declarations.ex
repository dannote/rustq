defmodule RustQ.Spec.Declarations do
  @moduledoc """
  Extracts typespec-related declarations from quoted Elixir source.

  This helper is intentionally source/AST-oriented: it is useful for codegen
  flows that load declaration modules with `Code.require_file/1` or RustQ
  config files before BEAM docs/spec chunks are available.
  """

  defstruct aliases: %{}, specs: [], defs: %{}

  @type spec_decl :: {atom(), [Macro.t()]}
  @type t :: %__MODULE__{
          aliases: %{optional({atom(), non_neg_integer()}) => RustQ.Meta.Type.t()},
          specs: [spec_decl()],
          defs: %{optional(atom()) => [atom()]}
        }

  @doc "Reads a source file and extracts type aliases, function specs, and def argument names."
  @spec from_file(Path.t()) :: t()
  def from_file(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!(file: path)
    |> from_quoted()
  end

  @doc "Extracts type aliases, function specs, and def argument names from quoted Elixir source."
  @spec from_quoted(Macro.t()) :: t()
  def from_quoted({:defmodule, _meta, [_module, [do: body]]}), do: from_quoted(body)

  def from_quoted(body) do
    {types, specs, defs} =
      body
      |> block_expressions()
      |> Enum.reduce({[], [], %{}}, fn
        {:@, meta, [{:type, _, [{:"::", _, [_name_ast, _type_ast]} = type_ast]}]},
        {types, specs, defs} ->
          {[{:type, type_ast, meta[:line] || 0} | types], specs, defs}

        {:@, _, [{:spec, _, [{:"::", _, [{name, _, arg_types}, _return]}]}]},
        {types, specs, defs} ->
          {types, specs ++ [{name, arg_types}], defs}

        {:def, _, [{name, _, args}, _body]}, {types, specs, defs} ->
          {types, specs, Map.put(defs, name, Enum.map(args || [], &arg_name!/1))}

        _other, acc ->
          acc
      end)

    %__MODULE__{aliases: RustQ.Spec.aliases(types), specs: specs, defs: defs}
  end

  defp arg_name!({name, _meta, context}) when is_atom(name) and is_atom(context), do: name

  defp arg_name!(other),
    do:
      raise(ArgumentError, "unsupported function declaration argument #{Macro.to_string(other)}")

  defp block_expressions({:__block__, _, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]
end
