defmodule RustQ.Meta.Typing do
  @moduledoc """
  Small bidirectional typing nucleus for Rusty-Elixir lowering.

  This module intentionally starts as an explicit, side-effect-free companion to
  `RustQ.Meta.Lower`: callers pass an `%Env{}` instead of relying on the
  lowerer's process dictionary. The lowerer can migrate individual positions to
  `synth/2` and `check/3` over time.
  """

  alias RustQ.Binding.Index, as: BindingIndex
  alias RustQ.Meta.Inference
  alias RustQ.Meta.Lower
  alias RustQ.Meta.Pattern
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  defmodule Env do
    @moduledoc "Typing environment threaded through synthesis/checking."
    defstruct vars: %{}, callables: %BindingIndex{}, rust_modules: %{}

    @type t :: %__MODULE__{
            vars: %{optional(atom()) => Type.t()},
            callables: BindingIndex.t(),
            rust_modules: %{optional([atom()]) => [atom()]}
          }
  end

  defmodule Check do
    @moduledoc "Result of checking an expression against an expected type."
    defstruct [:type, :coercion]

    @type coercion :: :none | :propagate | :some | :borrow | :mut_borrow | :unknown
    @type t :: %__MODULE__{type: Type.t() | nil, coercion: coercion()}
  end

  @type env_source :: Env.t() | keyword()

  @spec env(keyword()) :: Env.t()
  def env(opts \\ []) do
    %Env{
      vars: Keyword.get(opts, :vars, %{}),
      callables: BindingIndex.new(Keyword.get(opts, :callables)),
      rust_modules: Keyword.get(opts, :rust_modules, %{})
    }
  end

  @spec synth(Macro.t(), env_source()) :: Type.t() | nil
  def synth({name, _meta, context}, %Env{vars: vars}) when is_atom(name) and is_atom(context) do
    Map.get(vars, name)
  end

  def synth({:cast, _meta, [_expression, type_ast]}, %Env{}) do
    RustQ.Spec.type(type_ast)
  end

  def synth(call_ast, %Env{} = env) do
    Lower.callable_return_type(call_ast, callables: env.callables, rust_modules: env.rust_modules) ||
      synth_method_call(call_ast, env)
  end

  def synth(ast, opts) when is_list(opts), do: synth(ast, env(opts))

  @spec check(Macro.t(), Type.t(), env_source()) :: Check.t()
  def check(ast, %Type{} = expected, opts) when is_list(opts), do: check(ast, expected, env(opts))

  def check(ast, %Type{} = expected, %Env{} = env) do
    actual = synth(ast, env)

    %Check{type: actual, coercion: coercion(actual, expected)}
  end

  @spec expected_for_let(Macro.t(), Macro.t(), env_source()) :: Type.t() | nil
  def expected_for_let(pattern, expression, opts) when is_list(opts) do
    expected_for_let(pattern, expression, env(opts))
  end

  def expected_for_let(pattern, expression, %Env{} = env) do
    infer_pattern_type(pattern, env.vars) ||
      infer_pattern_type_from_call(pattern, expression, env)
  end

  @spec struct_field_type(Type.t(), atom()) :: Type.t() | nil
  def struct_field_type(%Type{meta: %{fields: fields}}, field)
      when is_atom(field) and is_list(fields) do
    fields
    |> Enum.find_value(fn
      {^field, %Type{} = type, _presence} -> type
      {^field, %Type{} = type} -> type
      _other -> nil
    end)
  end

  def struct_field_type(%Type{}, _field), do: nil

  @spec infer_downstream_let_types([Macro.t()], env_source(), map()) :: %{
          optional(atom()) => Type.t()
        }
  def infer_downstream_let_types(expressions, env_or_opts, callbacks \\ %{})

  def infer_downstream_let_types(expressions, opts, callbacks) when is_list(opts) do
    infer_downstream_let_types(expressions, env(opts), callbacks)
  end

  def infer_downstream_let_types(expressions, %Env{} = env, callbacks) when is_map(callbacks) do
    Inference.infer_downstream_let_types(expressions, env.vars, callbacks)
  end

  defp synth_method_call({{:., _, [receiver, function]}, _meta, args}, %Env{} = env)
       when is_atom(function) and is_list(args) do
    receiver
    |> synth(env)
    |> callable_target_from_type()
    |> then(&BindingIndex.return_type(env.callables, &1, function, length(args)))
  end

  defp synth_method_call(_ast, _env), do: nil

  defp infer_pattern_type({name, _meta, context}, vars) when is_atom(name) and is_atom(context),
    do: Map.get(vars, name)

  defp infer_pattern_type(_pattern, _vars), do: nil

  defp infer_pattern_type_from_call(pattern, expression, %Env{} = env) do
    with [_ | _] = elements <- Pattern.tuple_elements(pattern),
         %Type{} = call_type <- synth(expression, env),
         true <- Type.propagates?(call_type),
         %Type{kind: :tuple, meta: %{elements: types}} = inner <- Type.inner(call_type),
         true <- length(elements) == length(types) do
      inner
    else
      _no_tuple_match -> nil
    end
  end

  defp coercion(%Type{} = actual, %Type{} = expected) do
    cond do
      Type.compatible?(actual, expected) ->
        :none

      Type.propagates?(actual) and Type.compatible_with_expected?(Type.inner(actual), expected) ->
        :propagate

      expected.kind == :option and Type.compatible?(actual, Type.inner(expected)) ->
        :some

      ref_inner_compatible?(actual, expected) ->
        borrow_coercion(expected)

      Type.compatible_with_expected?(actual, expected) ->
        :none

      true ->
        :unknown
    end
  end

  defp coercion(_actual, _expected), do: :unknown

  defp ref_inner_compatible?(%Type{} = actual, %Type{} = expected) do
    case Type.ref_inner(expected) do
      %Type{} = inner -> Type.compatible?(actual, inner)
      nil -> false
    end
  end

  defp borrow_coercion(%Type{kind: :mut_ref}), do: :mut_borrow
  defp borrow_coercion(%Type{}), do: :borrow

  defp callable_target_from_type(%Type{kind: kind, meta: %{inner: %Type{} = inner}})
       when kind in [:ref, :mut_ref],
       do: callable_target_from_type(inner)

  defp callable_target_from_type(%Type{meta: %{syn_name: name}}) when is_binary(name), do: name

  defp callable_target_from_type(%Type{ast: %AST.TypeRef{inner: inner}}),
    do: callable_target_from_ast(inner)

  defp callable_target_from_type(%Type{ast: ast}), do: callable_target_from_ast(ast)
  defp callable_target_from_type(_type), do: nil

  defp callable_target_from_ast(%AST.TypePath{parts: [_ | _] = parts}),
    do: Enum.map_join(parts, "::", &to_string/1)

  defp callable_target_from_ast(%AST.TypeRaw{source: source}),
    do: raw_callable_target(source)

  defp callable_target_from_ast(_ast), do: nil

  defp raw_callable_target(source) when is_binary(source) do
    source
    |> String.replace(~r/^&\s*(mut\s+)?/, "")
    |> String.replace(~r/<.*$/, "")
    |> String.trim()
    |> case do
      "" -> nil
      target -> target
    end
  end
end
