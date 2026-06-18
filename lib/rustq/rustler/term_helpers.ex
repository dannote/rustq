defmodule RustQ.Rustler.TermHelpers do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust
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

  @templates %{
    get: ~R"""
    fn get<'a>(term: Term<'a>, key: rustler::Atom) -> Option<Term<'a>> {
        term.map_get(key).ok()
    }
    """,
    is_nil: ~R"""
    fn is_nil(term: Term) -> bool {
        term.is_atom() && term.atom_to_string().ok().as_deref() == Some("nil")
    }
    """,
    opt: ~R"""
    fn opt<'a>(term: Term<'a>, key: rustler::Atom) -> Option<Term<'a>> {
        get(term, key).filter(|t| !is_nil(*t))
    }
    """,
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
    bool_val: ~R"""
    fn bool_val(term: Term, key: rustler::Atom) -> bool {
        get(term, key)
            .and_then(|t| t.decode::<bool>().ok())
            .unwrap_or(false)
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
    list_val: ~R"""
    fn list_val<'a>(term: Term<'a>, key: rustler::Atom) -> Vec<Term<'a>> {
        get(term, key)
            .and_then(|t| t.decode::<Vec<Term>>().ok())
            .unwrap_or_default()
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

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    type_key = Keyword.get(opts, :type_key, "atoms::r#type()")

    opts
    |> names()
    |> Enum.map(&template!/1)
    |> Enum.map(fn template ->
      template
      |> RustQ.render!("rustler_term_helper.rs", bind: [type_key: Rust.expr(type_key)])
      |> Rust.item()
    end)
  end

  defp names(opts), do: HelperSelection.names(opts, @names)

  defp template!(name), do: Map.fetch!(@templates, name)
end
