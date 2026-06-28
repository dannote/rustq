defmodule RustQ.Meta.RustMacro do
  @moduledoc """
  Builds compact Rust `macro_rules!` items from Rusty-Elixir `defrustmacro`
  declarations.

  A `defrustmacro` body is lowered through the same Rusty-Elixir pipeline used by
  `defrust`, while its arguments are tracked as Rust macro fragments. This keeps
  macro definitions semantic at the Elixir layer and confines Rust token-tree
  syntax to the generated backend item.
  """

  alias RustQ.Diagnostic
  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Meta.Lower
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render

  defmodule Definition do
    @moduledoc """
    Normalized `defrustmacro` declaration metadata.
    """

    @enforce_keys [:name, :args, :call_ast, :body_ast]
    defstruct [:name, :args, :call_ast, :body_ast, :rust_module]

    @type fragment :: :expr | :ty
    @type arg :: {atom(), fragment()}
    @type t :: %__MODULE__{
            name: atom(),
            args: [arg()],
            call_ast: Macro.t(),
            body_ast: Macro.t(),
            rust_module: [atom()] | nil
          }
  end

  defmodule Item do
    @moduledoc """
    Rust AST item emitted from a normalized `defrustmacro` declaration.
    """

    @enforce_keys [:ast]
    defstruct [:ast, :rust_module]

    @type t :: %__MODULE__{ast: AST.MacroItem.t(), rust_module: [atom()] | nil}
  end

  @type index :: %{optional(atom()) => Definition.t()}

  @doc false
  @spec definitions([{Macro.t(), Macro.t(), [atom()] | nil}]) :: [Definition.t()]
  def definitions(attributes) do
    Enum.map(attributes, fn {call_ast, body_ast, rust_module} ->
      {name, args} = signature!(call_ast)

      %Definition{
        name: name,
        args: args,
        call_ast: call_ast,
        body_ast: body_ast,
        rust_module: rust_module
      }
    end)
  end

  @doc false
  @spec index!([Definition.t()]) :: index()
  def index!(definitions) do
    Enum.reduce(definitions, %{}, fn %Definition{name: name, call_ast: call_ast} = definition,
                                     index ->
      if Map.has_key?(index, name) do
        Diagnostic.defrust(
          :duplicate_defrustmacro,
          call_ast,
          "duplicate defrustmacro #{name}",
          suggestion: "Use a single defrustmacro per Rust macro name for now."
        )
      end

      Map.put(index, name, definition)
    end)
  end

  @doc false
  @spec items([Definition.t()], map(), Macro.Env.t(), [term()], index()) :: [Item.t()]
  def items(definitions, rust_modules, env, callables, index) do
    Enum.map(definitions, &item(&1, rust_modules, env, callables, index))
  end

  @doc false
  @spec fragments(Definition.t()) :: [Definition.fragment()]
  def fragments(%Definition{args: args}), do: Enum.map(args, &elem(&1, 1))

  defp item(%Definition{} = definition, rust_modules, env, callables, index) do
    body_ast = MetaAST.expand_body_macros(definition.body_ast, env)

    body =
      Lower.quoted_body(body_ast, nil, %{},
        rust_modules: rust_modules,
        callables: callables,
        macro_vars: Map.new(definition.args),
        rust_macros: index
      )

    %Item{
      ast: %AST.MacroItem{source: source(definition.name, definition.args, body)},
      rust_module: definition.rust_module
    }
  rescue
    error in Diagnostic.Error ->
      raise_diagnostic(definition, error.diagnostic)

    error in [ArgumentError, FunctionClauseError] ->
      raise_diagnostic(definition, error)
  end

  defp signature!({name, _meta, args}) when is_atom(name) and is_list(args) do
    {plain_args, keyword_args} = split_args(args)

    positional = Enum.map(plain_args, &arg!(&1, :expr))
    annotated = Enum.map(keyword_args, fn {arg_name, fragment} -> arg!(arg_name, fragment) end)

    args = positional ++ annotated
    validate_unique_args!(name, args)

    {name, args}
  end

  defp signature!(other) do
    Diagnostic.defrust(
      :invalid_defrustmacro_signature,
      other,
      "invalid defrustmacro signature",
      suggestion: "Use defrustmacro name(arg, type_arg: :ty) do ... end."
    )
  end

  defp split_args(args) do
    case Enum.split(args, max(length(args) - 1, 0)) do
      {plain, [[{_name, _fragment} | _] = keyword]} -> {plain, keyword}
      {_plain, [keyword]} when is_list(keyword) -> invalid_keyword_args!(keyword)
      {plain, []} -> {plain, []}
      {plain, [last]} -> {plain ++ [last], []}
    end
  end

  defp validate_unique_args!(macro_name, args) do
    args
    |> Enum.map(&elem(&1, 0))
    |> Enum.find(fn name -> Enum.count(args, &(elem(&1, 0) == name)) > 1 end)
    |> case do
      nil ->
        :ok

      duplicate ->
        Diagnostic.defrust(
          :duplicate_defrustmacro_argument,
          duplicate,
          "duplicate argument #{duplicate} in defrustmacro #{macro_name}"
        )
    end
  end

  @spec invalid_keyword_args!(term()) :: no_return()
  defp invalid_keyword_args!(args) do
    Diagnostic.defrust(
      :invalid_defrustmacro_argument,
      args,
      "invalid defrustmacro annotated arguments",
      suggestion: "Use keyword annotations such as type: :ty."
    )
  end

  defp arg!({name, _meta, context}, fragment) when is_atom(name) and is_atom(context),
    do: arg!(name, fragment)

  defp arg!(name, fragment) when is_atom(name) and fragment in [:expr, :ty], do: {name, fragment}

  defp arg!(name, fragment) when is_atom(name) do
    Diagnostic.defrust(
      :unsupported_defrustmacro_fragment,
      name,
      "unsupported Rust macro fragment #{inspect(fragment)} for #{name}",
      suggestion: "Currently defrustmacro supports :expr and :ty fragments."
    )
  end

  defp arg!(arg, _fragment) do
    Diagnostic.defrust(
      :invalid_defrustmacro_argument,
      arg,
      "invalid defrustmacro argument",
      suggestion: "Use plain variables and optional keyword fragment annotations."
    )
  end

  defp source(name, args, body) do
    pattern = Enum.map_join(args, ", ", fn {arg_name, fragment} -> "$#{arg_name}:#{fragment}" end)

    rendered_body =
      body
      |> Enum.map_join("\n", &(Render.render_stmt(&1) |> IO.iodata_to_binary()))
      |> clean_macro_metavariable_spacing()

    "macro_rules! #{name} {\n    (#{pattern}) => {{\n#{indent(rendered_body)}\n    }};\n}"
  end

  defp clean_macro_metavariable_spacing(source) do
    source
    |> String.replace(~r/\$([a-zA-Z_][a-zA-Z0-9_]*)\s+/, ~S|$\1|)
    |> String.replace(" ?", "?")
  end

  defp indent(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &["        ", &1])
  end

  @spec raise_diagnostic(Definition.t(), term()) :: no_return()
  defp raise_diagnostic(%Definition{} = definition, cause) do
    Diagnostic.defrust(
      :defrustmacro_failed,
      definition.body_ast,
      "failed to build defrustmacro #{definition.name}/#{length(definition.args)}: #{diagnostic_message(cause)}",
      details: %{macro: definition.name, arity: length(definition.args), cause: cause}
    )
  end

  defp diagnostic_message(%Diagnostic{} = diagnostic), do: diagnostic.message
  defp diagnostic_message(error), do: Exception.message(error)
end
