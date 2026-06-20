defmodule RustQ.Binding.Index do
  @moduledoc """
  Lookup table for normalized RustQ callable metadata.

  The index stores `RustQ.Binding.Callable` values under local and target-qualified
  call keys. Method callables are indexed both by their full Rust signature arity
  and, when they include a receiver/self argument, by the Elixir-style call arity
  that excludes the receiver. This lets lowering ask for `Canvas.draw_rect(rect)`
  even when the Rust signature is `draw_rect(&self, rect: Rect)`.
  """

  alias RustQ.Binding.Callable
  alias RustQ.Meta.Type

  defstruct by_key: %{}

  @type key :: {String.t() | nil, String.t(), non_neg_integer()}
  @type t :: %__MODULE__{by_key: %{optional(key()) => Callable.t()}}

  @doc "Builds a callable lookup index."
  @spec new([Callable.t()] | t() | nil) :: t()
  def new(nil), do: %__MODULE__{}
  def new(%__MODULE__{} = index), do: index

  def new(callables) when is_list(callables) do
    Enum.reduce(callables, %__MODULE__{}, &put(&2, &1))
  end

  @doc "Adds a callable to the index under all lookup keys it supports."
  @spec put(t(), Callable.t()) :: t()
  def put(%__MODULE__{} = index, %Callable{} = callable) do
    keys = callable_keys(callable)
    by_key = Enum.reduce(keys, index.by_key, &Map.put(&2, &1, callable))
    %{index | by_key: by_key}
  end

  @doc "Fetches a callable by optional target, function name, and call arity."
  @spec fetch(t(), String.t() | atom() | nil, String.t() | atom(), non_neg_integer()) ::
          {:ok, Callable.t()} | :error
  def fetch(%__MODULE__{} = index, target, name, arity) do
    Map.fetch(index.by_key, key(target, name, arity))
  end

  @doc "Returns a callable by optional target, function name, and call arity or `nil`."
  @spec get(t(), String.t() | atom() | nil, String.t() | atom(), non_neg_integer()) ::
          Callable.t() | nil
  def get(%__MODULE__{} = index, target, name, arity) do
    case fetch(index, target, name, arity) do
      {:ok, callable} -> callable
      :error -> nil
    end
  end

  @doc "Returns the return type for a callable lookup or `nil` when unknown/unit."
  @spec return_type(t(), String.t() | atom() | nil, String.t() | atom(), non_neg_integer()) ::
          Type.t() | nil
  def return_type(%__MODULE__{} = index, target, name, arity) do
    case get(index, target, name, arity) do
      %Callable{returns: %Type{} = type} -> type
      _missing_or_unit -> nil
    end
  end

  @doc "Returns expected argument types for a callable lookup."
  @spec argument_types(t(), String.t() | atom() | nil, String.t() | atom(), non_neg_integer()) ::
          [Type.t()] | nil
  def argument_types(%__MODULE__{} = index, target, name, arity) do
    case get(index, target, name, arity) do
      %Callable{} = callable -> argument_types_for_arity(callable, arity)
      nil -> nil
    end
  end

  defp callable_keys(%Callable{name: name, target: target, args: args}) do
    rust_arity = length(args)

    keys = [key(target, name, rust_arity)]

    if receiver_arg?(List.first(args)) and rust_arity > 0 do
      [key(target, name, rust_arity - 1) | keys]
    else
      keys
    end
    |> Enum.uniq()
  end

  defp argument_types_for_arity(%Callable{args: args}, arity) when length(args) == arity,
    do: Enum.map(args, & &1.type)

  defp argument_types_for_arity(%Callable{args: [_receiver | args]} = callable, arity) do
    if receiver_arg?(List.first(callable.args)) and length(args) == arity do
      Enum.map(args, & &1.type)
    end
  end

  defp receiver_arg?(%{name: "self"}), do: true
  defp receiver_arg?(_arg), do: false

  defp key(nil, name, arity), do: {nil, name_part(name), arity}
  defp key(target, name, arity), do: {target_part(target), name_part(name), arity}

  defp target_part(target) when is_atom(target), do: Atom.to_string(target)
  defp target_part(target) when is_binary(target), do: target

  defp name_part(name) when is_atom(name), do: Atom.to_string(name)
  defp name_part(name) when is_binary(name), do: name
end
