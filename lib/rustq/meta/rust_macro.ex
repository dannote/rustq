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
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render

  defmodule Definition do
    @moduledoc """
    Normalized `defrustmacro` declaration metadata.
    """

    @enforce_keys [:name, :args, :call_ast, :body_ast]
    defstruct [:name, :args, :call_ast, :body_ast, :rust_module]

    @type fragment :: :expr | :ty | :ident | :literal
    @type arg ::
            {atom(), fragment()}
            | {:labeled, atom(), atom(), fragment()}
            | {:repeat, atom(), [arg()]}
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

    @enforce_keys [:name, :ast]
    defstruct [:name, :ast, :rust_module]

    @type t :: %__MODULE__{name: atom(), ast: AST.MacroItem.t(), rust_module: [atom()] | nil}
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
  def fragments(%Definition{args: args}) do
    args
    |> Enum.reject(&match?({:repeat, _name, _args}, &1))
    |> Enum.map(fn
      {_name, fragment} -> fragment
      {:labeled, _label, _name, fragment} -> fragment
    end)
  end

  defp item(%Definition{} = definition, rust_modules, env, callables, index) do
    ast =
      case item_macro_body(definition.body_ast, definition, rust_modules, callables, index) do
        {:ok, source} ->
          %AST.MacroItem{source: source}

        :error ->
          body_ast = MetaAST.expand_body_macros(definition.body_ast, env)

          body =
            Lower.quoted_body(body_ast, nil, %{},
              rust_modules: rust_modules,
              callables: callables,
              macro_vars: macro_var_map(definition.args),
              rust_macros: index
            )

          %AST.MacroItem{source: source(definition.name, definition.args, body)}
      end

    %Item{name: definition.name, ast: ast, rust_module: definition.rust_module}
  rescue
    error in Diagnostic.Error ->
      raise_diagnostic(definition, error.diagnostic)

    error in [ArgumentError, FunctionClauseError] ->
      raise_diagnostic(definition, error)
  end

  defp signature!({name, _meta, args}) when is_atom(name) and is_list(args) do
    {plain_args, keyword_args} = split_args(args)

    positional = Enum.map(plain_args, &arg!(&1, :expr))
    annotated = Enum.map(keyword_args, &keyword_arg!/1)

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
    |> capture_names()
    |> duplicate_capture()
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

  defp duplicate_capture(names) do
    {_seen, duplicate} =
      Enum.reduce_while(names, {MapSet.new(), nil}, fn name, {seen, _duplicate} ->
        if MapSet.member?(seen, name) do
          {:halt, {seen, name}}
        else
          {:cont, {MapSet.put(seen, name), nil}}
        end
      end)

    duplicate
  end

  defp capture_names(args) do
    Enum.flat_map(args, fn
      {name, _fragment} -> [name]
      {:labeled, _label, name, _fragment} -> [name]
      {:repeat, name, args} -> [name | capture_names(args)]
    end)
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

  defp keyword_arg!({label, {:repeat, _meta, [[do: body]]}}) when is_atom(label) do
    {:repeat, label, repeat_args!(body)}
  end

  defp keyword_arg!({label, {name, _meta, [fragment]}})
       when is_atom(label) and is_atom(name) and is_atom(fragment) do
    {:labeled, label, name, fragment!(name, fragment)}
  end

  defp keyword_arg!({arg_name, fragment}), do: arg!(arg_name, fragment)

  defp repeat_args!({:__block__, _meta, expressions}), do: Enum.map(expressions, &repeat_arg!/1)
  defp repeat_args!(expression), do: [repeat_arg!(expression)]

  defp repeat_arg!({name, _meta, [fragment]}) when is_atom(name) and is_atom(fragment),
    do: {name, fragment!(name, fragment)}

  defp repeat_arg!(other) do
    Diagnostic.defrust(
      :invalid_defrustmacro_repeat,
      other,
      "invalid defrustmacro repeat capture",
      suggestion: "Use captures such as field_id(:literal) inside repeat blocks."
    )
  end

  defp arg!({name, _meta, context}, fragment) when is_atom(name) and is_atom(context),
    do: arg!(name, fragment)

  defp arg!(name, fragment) when is_atom(name), do: {name, fragment!(name, fragment)}

  defp arg!(arg, _fragment) do
    Diagnostic.defrust(
      :invalid_defrustmacro_argument,
      arg,
      "invalid defrustmacro argument",
      suggestion: "Use plain variables and optional keyword fragment annotations."
    )
  end

  defp fragment!(_name, fragment) when fragment in [:expr, :ty, :ident, :literal], do: fragment

  defp fragment!(name, fragment) when is_atom(name) do
    Diagnostic.defrust(
      :unsupported_defrustmacro_fragment,
      name,
      "unsupported Rust macro fragment #{inspect(fragment)} for #{name}",
      suggestion: "Currently defrustmacro supports :expr and :ty fragments."
    )
  end

  defp item_macro_body(
         {:__block__, _meta, expressions},
         definition,
         rust_modules,
         callables,
         index
       ) do
    spec = Enum.find_value(expressions, &spec_ast/1)
    defrust = Enum.find_value(expressions, &defrust_ast/1)

    if spec && defrust do
      {:ok, item_macro_source(definition, spec, defrust, rust_modules, callables, index)}
    else
      :error
    end
  end

  defp item_macro_body(expression, definition, rust_modules, callables, index),
    do:
      item_macro_body({:__block__, [], [expression]}, definition, rust_modules, callables, index)

  defp spec_ast({:@, _meta, [{:spec, _spec_meta, [{:"::", _op_meta, [call_ast, return_ast]}]}]}),
    do: {call_ast, return_ast}

  defp spec_ast(_expression), do: nil

  defp defrust_ast({:defrust, _meta, [call_ast, [do: body_ast]]}), do: {call_ast, body_ast}
  defp defrust_ast(_expression), do: nil

  defp item_macro_source(
         definition,
         {spec_call, return_ast},
         {call_ast, body_ast},
         rust_modules,
         callables,
         index
       ) do
    {_spec_name, _spec_meta, arg_type_asts} = spec_call
    {name_ast, _call_meta, arg_asts} = call_ast

    arg_names = Enum.map(arg_asts, &capture_var_name!/1)
    arg_types = Enum.map(arg_type_asts, &Type.parse(&1, %{}))
    return_type = Type.parse(return_ast, %{})
    vars = Map.new(Enum.zip(arg_names, arg_types))

    body =
      Lower.quoted_body(body_ast, return_type, vars,
        rust_modules: rust_modules,
        callables: callables,
        macro_vars: macro_var_map(definition.args),
        rust_macros: index
      )

    pattern = item_pattern(definition.args)

    expansion =
      function_expansion(
        name_ast,
        arg_names,
        arg_types,
        return_type,
        body,
        macro_var_map(definition.args)
      )

    "macro_rules! #{definition.name} {\n#{indent("(#{pattern}) => {\n#{indent(expansion)}\n};")}\n}"
  end

  defp capture_var_name!({name, _meta, context}) when is_atom(name) and is_atom(context), do: name

  defp capture_var_name!(other) do
    Diagnostic.defrust(
      :invalid_defrustmacro_item_arg,
      other,
      "invalid defrustmacro item argument",
      suggestion: "Use plain captured argument names in inner defrust, such as defrust name(env)."
    )
  end

  defp item_pattern(args), do: Enum.map_join(args, "\n", &item_pattern_arg/1)

  defp item_pattern_arg({:labeled, :fn, name, fragment}), do: "fn $#{name}:#{fragment};"
  defp item_pattern_arg({:labeled, label, name, fragment}), do: "#{label} $#{name}:#{fragment};"
  defp item_pattern_arg({name, fragment}), do: "$#{name}:#{fragment};"

  defp item_pattern_arg({:repeat, :fields, args}) do
    [field_id, field_name, field_mode, field_decode] = args

    "fields [$(#{capture_pattern(field_id)} => #{capture_pattern(field_name)}: #{capture_pattern(field_mode)} #{capture_pattern(field_decode)};)*]"
  end

  defp item_pattern_arg({:repeat, name, args}) do
    captures = Enum.map_join(args, " ", &capture_pattern/1)
    "#{name} [$(#{captures};)*]"
  end

  defp capture_pattern({name, fragment}), do: "$#{name}:#{fragment}"

  defp function_expansion(name_ast, arg_names, arg_types, return_type, body, macro_vars) do
    name = macro_capture_source(name_ast, macro_vars)

    args =
      Enum.zip(arg_names, arg_types)
      |> Enum.map_join(", ", fn {arg_name, type} -> "$#{arg_name}: #{render_type(type)}" end)

    rendered_body =
      body
      |> Enum.map_join("\n", &render_macro_item_stmt/1)
      |> clean_macro_metavariable_spacing()

    "fn #{name}<'a>(#{args}) -> #{render_type(return_type)} {\n#{indent(rendered_body)}\n}"
  end

  defp render_macro_item_stmt(stmt) do
    stmt
    |> Render.render_stmt()
    |> IO.iodata_to_binary()
    |> format_repeated_array_call()
  end

  defp format_repeated_array_call(source) do
    Regex.replace(
      ~r/^([a-zA-Z_][a-zA-Z0-9_]*)\((.*), &\[\$\((.*)\)\*\]\)$/,
      source,
      fn _all, function, prefix, repeated ->
        args = split_top_level_args(prefix)

        [
          function,
          "(\n",
          args |> Enum.map(&["    ", &1, ","]) |> Enum.intersperse("\n"),
          "\n    &[\n",
          "        $(",
          repeated,
          ")*\n",
          "    ],\n",
          ")"
        ]
        |> IO.iodata_to_binary()
      end
    )
  end

  defp split_top_level_args(source), do: split_top_level_args(String.graphemes(source), [], [], 0)

  defp split_top_level_args([], current, acc, _depth) do
    [current | acc]
    |> Enum.reverse()
    |> Enum.map(&(&1 |> Enum.reverse() |> Enum.join() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
  end

  defp split_top_level_args(["," | rest], current, acc, 0),
    do: split_top_level_args(rest, [], [current | acc], 0)

  defp split_top_level_args([char | rest], current, acc, depth) when char in ["(", "[", "{"] do
    split_top_level_args(rest, [char | current], acc, depth + 1)
  end

  defp split_top_level_args([char | rest], current, acc, depth) when char in [")", "]", "}"] do
    split_top_level_args(rest, [char | current], acc, max(depth - 1, 0))
  end

  defp split_top_level_args([char | rest], current, acc, depth) do
    split_top_level_args(rest, [char | current], acc, depth)
  end

  defp macro_capture_source({name, _meta, args}, macro_vars)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(macro_vars, name), do: "$#{name}", else: Atom.to_string(name)
  end

  defp macro_capture_source({name, _meta, context}, macro_vars)
       when is_atom(name) and is_atom(context) do
    if Map.has_key?(macro_vars, name), do: "$#{name}", else: Atom.to_string(name)
  end

  defp macro_capture_source(other, macro_vars) when is_atom(other) do
    if Map.has_key?(macro_vars, other), do: "$#{other}", else: Atom.to_string(other)
  end

  defp render_type(%Type{} = type), do: type.ast |> Render.render_type() |> IO.iodata_to_binary()

  defp macro_var_map(args) do
    args
    |> Enum.flat_map(fn
      {name, fragment} -> [{name, fragment}]
      {:labeled, _label, name, fragment} -> [{name, fragment}]
      {:repeat, _name, args} -> macro_var_map(args)
    end)
    |> Map.new()
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
