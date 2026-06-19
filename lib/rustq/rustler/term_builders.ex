defmodule RustQ.Rustler.TermBuilders do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Rust
  alias RustQ.Rustler.HelperSelection
  alias RustQ.Type, as: R

  @names [:map_from_terms, :struct_from_terms]
  @function_names %{
    map_from_terms: :make_map_from_terms,
    struct_from_terms: :make_struct_from_terms
  }

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

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    opts
    |> HelperSelection.names(@names)
    |> Enum.map(&rusty_item/1)
  end

  defp rusty_item(name) do
    function_name = Map.fetch!(@function_names, name)
    RustQ.Meta.item(__MODULE__, function_name)
  end
end
