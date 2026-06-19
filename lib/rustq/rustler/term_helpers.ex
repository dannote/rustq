defmodule RustQ.Rustler.TermHelpers do
  @moduledoc false

  use RustQ.Sigil
  use RustQ.Meta

  alias RustQ.Rust
  alias RustQ.Type, as: R
  alias RustQ.Rustler.HelperSelection

  @names [
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

  @rusty_names [:get, :is_nil, :opt, :bool_val, :list_val]

  @templates %{
    str_val: ~R"""
    fn str_val<'a>(term: Term<'a>, key: rustler::Atom) -> String {
        match get(term, key) {
            Some(t) => t
                .decode::<String>()
                .or_else(|_| t.atom_to_string())
                .unwrap_or_default(),
            None => String::new(),
        }
    }
    """,
    f64_val: ~R"""
    fn f64_val(term: Term, key: rustler::Atom) -> f64 {
        get(term, key)
            .and_then(|t| {
                t.decode::<f64>()
                    .ok()
                    .or_else(|| t.decode::<i64>().ok().map(|i| i as f64))
            })
            .unwrap_or(0.0)
    }
    """,
    type_atom: ~R"""
    fn type_atom(term: Term) -> Option<rustler::Atom> {
        get(term, __rq_type_key!()).and_then(|t| t.decode::<rustler::Atom>().ok())
    }
    """,
    type_eq: ~R"""
    fn type_eq(term: Term, expected: rustler::Atom) -> bool {
        type_atom(term) == Some(expected)
    }
    """,
    type_str: ~R"""
    fn type_str(term: Term) -> String {
        get(term, __rq_type_key!())
            .and_then(|t| t.atom_to_string().ok())
            .unwrap_or_else(|| "<no type>".into())
    }
    """
  }

  @spec get(term(), R.path({:rustler, :Atom})) :: R.option(term())
  defrust get(term, key) do
    case term.map_get(key) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  @spec is_nil(term()) :: R.bool()
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

  @spec bool_val(term(), R.path({:rustler, :Atom})) :: R.bool()
  defrust bool_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        case decode_as(value, R.bool()) do
          {:ok, decoded} -> decoded
          {:error, _reason} -> false
        end

      :none ->
        false
    end
  end

  @spec list_val(term(), R.path({:rustler, :Atom})) :: R.vec(term())
  defrust list_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        case decode_as(value, R.vec(term())) do
          {:ok, decoded} -> decoded
          {:error, _reason} -> Vec.new()
        end

      :none ->
        Vec.new()
    end
  end

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    type_key = Keyword.get(opts, :type_key, "atoms::r#type()")

    opts
    |> names()
    |> Enum.map(&helper_item(&1, type_key))
  end

  defp names(opts), do: HelperSelection.names(opts, @names)

  defp helper_item(name, _type_key) when name in @rusty_names do
    __rustq_asts__()
    |> Enum.find(&(&1.name == name))
    |> RustQ.Rust.AST.Render.render_item()
    |> Rust.item()
  end

  defp helper_item(name, type_key) do
    name
    |> template!()
    |> RustQ.render!("rustler_term_helper.rs", bind: [type_key: Rust.expr(type_key)])
    |> Rust.item()
  end

  defp template!(name), do: Map.fetch!(@templates, name)
end
