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

    @type coercion ::
            :none
            | :propagate
            | :some
            | :borrow
            | :mut_borrow
            | :propagate_borrow
            | :propagate_mut_borrow
            | :unknown
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

  def synth({:__aliases__, _meta, parts}, %Env{vars: vars}) when is_list(parts) do
    parts
    |> List.last()
    |> then(&Map.get(vars, &1))
  end

  def synth({:cast, _meta, [_expression, type_ast]}, %Env{}) do
    RustQ.Spec.type(type_ast)
  end

  def synth({:unwrap!, _meta, [expression]}, %Env{} = env) do
    case synth(expression, env) do
      %Type{} = type -> Type.inner(type)
      nil -> nil
    end
  end

  def synth(call_ast, %Env{} = env) do
    Lower.callable_return_type(
      call_ast,
      callables: env.callables,
      rust_modules: env.rust_modules,
      vars: env.vars
    ) || synth_method_call(call_ast, env)
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
      infer_pattern_type_from_call(pattern, expression, env) ||
      synth(expression, env)
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
    inferred = Inference.infer_downstream_let_types(expressions, env.vars, callbacks)
    rhs_types = non_propagating_let_rhs_types(expressions, env)

    inferred_types =
      Map.new(inferred, fn {name, type} ->
        {name, inferred_binding_type(type, Map.get(rhs_types, name))}
      end)

    Map.merge(rhs_types, inferred_types)
  end

  defp synth_method_call({{:., _, [receiver, :unwrap]}, _meta, []}, %Env{} = env) do
    case synth(receiver, env) do
      %Type{} = type -> Type.inner(type)
      nil -> nil
    end
  end

  defp synth_method_call({{:., _, [receiver, :unwrap_or]}, _meta, [_default]}, %Env{} = env) do
    receiver
    |> synth(env)
    |> option_unwrap_type()
  end

  defp synth_method_call({{:., _, [receiver, :as_ref]}, _meta, []}, %Env{} = env) do
    receiver
    |> synth(env)
    |> option_as_ref_type()
  end

  defp synth_method_call({{:., _, [receiver, :ok_or]}, _meta, [_error]}, %Env{} = env) do
    receiver
    |> synth(env)
    |> option_ok_or_type()
  end

  defp synth_method_call({{:., _, [receiver, :get]}, _meta, [_index]}, %Env{} = env) do
    receiver
    |> synth(env)
    |> slice_get_type()
  end

  defp synth_method_call({{:., _, [receiver, field]}, _meta, []} = ast, %Env{} = env)
       when is_atom(field) do
    field_type(synth(receiver, env), field) || synth_method_return(ast, env)
  end

  defp synth_method_call({{:., _, [_receiver, function]}, _meta, args} = ast, %Env{} = env)
       when is_atom(function) and is_list(args),
       do: synth_method_return(ast, env)

  defp synth_method_call(_ast, _env), do: nil

  defp synth_method_return({{:., _, [receiver, function]}, _meta, args}, %Env{} = env)
       when is_atom(function) and is_list(args) do
    receiver
    |> synth(env)
    |> callable_target_from_type()
    |> then(&BindingIndex.return_type(env.callables, &1, function, length(args)))
  end

  defp field_type(%Type{} = type, field) when is_atom(field) do
    type
    |> field_receiver_type()
    |> struct_field_type(field)
  end

  defp field_type(_type, _field), do: nil

  defp field_receiver_type(%Type{} = type), do: Type.ref_inner(type) || type

  defp slice_get_type(%Type{kind: :slice, meta: %{inner: %Type{} = inner}}),
    do: option_type(ref_type(inner))

  defp slice_get_type(%Type{ast: %AST.TypeRef{inner: %AST.TypeSlice{inner: inner}}}),
    do: option_type(ref_type(%Type{kind: :type, ast: inner, rust: render_type(inner)}))

  defp slice_get_type(_type), do: nil

  defp ref_type(%Type{} = inner),
    do: %Type{
      kind: :ref,
      rust: "&#{inner.rust}",
      ast: %AST.TypeRef{inner: inner.ast},
      meta: %{inner: inner}
    }

  defp option_type(%Type{} = inner),
    do: %Type{
      kind: :option,
      rust: "Option<#{inner.rust}>",
      ast: %AST.TypeOption{inner: inner.ast},
      meta: %{inner: inner}
    }

  defp result_type(%Type{} = ok),
    do: %Type{
      kind: :result,
      rust: "Result<#{ok.rust}, rustler::Error>",
      ast: %AST.TypeResult{ok: ok.ast, error: %AST.TypeRaw{source: "rustler::Error"}},
      meta: %{ok: ok}
    }

  defp option_as_ref_type(%Type{kind: :option} = type) do
    case Type.inner(type) do
      %Type{} = inner -> option_type(ref_type(inner))
      nil -> nil
    end
  end

  defp option_as_ref_type(_type), do: nil

  defp option_ok_or_type(%Type{kind: :option} = type) do
    case Type.inner(type) do
      %Type{} = inner -> result_type(inner)
      nil -> nil
    end
  end

  defp option_ok_or_type(_type), do: nil

  defp option_unwrap_type(%Type{kind: :option} = type), do: Type.inner(type)

  defp option_unwrap_type(%Type{} = type) do
    case Type.inner(type) do
      %Type{kind: :option} = option_type ->
        if Type.propagates?(type), do: Type.inner(option_type)

      _other ->
        nil
    end
  end

  defp option_unwrap_type(_type), do: nil

  defp render_type(ast), do: ast |> RustQ.Rust.AST.Render.render_type() |> IO.iodata_to_binary()

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

  defp inferred_binding_type(%Type{} = inferred, %Type{} = rhs) do
    if propagated_rhs_for_inferred_binding?(rhs, inferred), do: inferred, else: rhs
  end

  defp inferred_binding_type(inferred, _rhs), do: inferred

  defp propagated_rhs_for_inferred_binding?(%Type{} = rhs, %Type{} = inferred) do
    Type.propagates?(rhs) and
      (not Type.propagates?(inferred) or Type.compatible_with_expected?(Type.inner(rhs), inferred))
  end

  defp non_propagating_let_rhs_types(expressions, %Env{} = env) do
    expressions
    |> Enum.flat_map(&let_rhs_type(&1, env))
    |> Map.new()
    |> Map.reject(fn {_name, type} -> Type.propagates?(type) end)
  end

  defp let_rhs_type({:=, _meta, [{name, _pattern_meta, context}, expression]}, %Env{} = env)
       when is_atom(name) and is_atom(context) do
    case synth(expression, env) do
      %Type{} = type -> [{name, type}]
      nil -> []
    end
  end

  defp let_rhs_type(_expression, _env), do: []

  defp coercion(%Type{} = actual, %Type{} = expected) do
    cond do
      Type.compatible?(actual, expected) ->
        :none

      option_adapter_compatible?(actual, expected) ->
        :none

      Type.propagates?(actual) and Type.compatible_with_expected?(Type.inner(actual), expected) ->
        :propagate

      Type.propagates?(actual) and ref_inner_compatible?(Type.inner(actual), expected) ->
        propagate_borrow_coercion(expected)

      expected.kind == :option and Type.compatible?(actual, Type.inner(expected)) ->
        :some

      ref_inner_compatible?(actual, expected) ->
        borrow_coercion(expected)

      vec_slice_compatible?(actual, expected) ->
        :borrow

      Type.compatible_with_expected?(actual, expected) ->
        :none

      true ->
        :unknown
    end
  end

  defp coercion(_actual, _expected), do: :unknown

  defp option_adapter_compatible?(%Type{} = actual, %Type{} = expected) do
    case expected_option_type(expected) do
      %Type{} = option -> Type.compatible?(actual, option)
      nil -> false
    end
  end

  defp expected_option_type(%Type{kind: :option} = type), do: type

  defp expected_option_type(%Type{kind: :impl_trait, meta: %{traits: traits}}) do
    Enum.find_value(traits, fn
      %Type{meta: %{syn_name: "Into", args: [%Type{kind: :option} = option]}} -> option
      %Type{} = trait -> expected_option_type(trait)
      _trait -> nil
    end)
  end

  defp expected_option_type(%Type{}), do: nil

  defp ref_inner_compatible?(%Type{} = actual, %Type{} = expected) do
    case Type.ref_inner(expected) do
      %Type{} = inner -> Type.compatible?(actual, inner) or vec_slice_compatible?(actual, inner)
      nil -> false
    end
  end

  defp vec_slice_compatible?(%Type{} = actual, %Type{} = expected_inner) do
    with %Type{} = vec_inner <- Type.vec_inner(actual),
         %Type{} = slice_inner <- Type.slice_inner(expected_inner) do
      Type.compatible?(vec_inner, slice_inner)
    else
      _other -> false
    end
  end

  defp borrow_coercion(%Type{kind: :mut_ref}), do: :mut_borrow
  defp borrow_coercion(%Type{}), do: :borrow

  defp propagate_borrow_coercion(%Type{kind: :mut_ref}), do: :propagate_mut_borrow
  defp propagate_borrow_coercion(%Type{}), do: :propagate_borrow

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
