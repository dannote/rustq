defmodule RustQ.Rustler.OptsHelpers do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust
  alias RustQ.Rustler.HelperSelection

  @names [
    :decode_opts,
    :opt_term,
    :opt_f32,
    :opt_f32_option,
    :opt_f32_default,
    :opt_bool_option,
    :opt_atom_option
  ]

  @templates %{
    decode_opts: ~R"""
    fn decode_opts<'a>(term: Term<'a>) -> NifResult<Vec<(Atom, Term<'a>)>> {
        term.map_get(__rq_key!())?.decode::<Vec<(Atom, Term<'a>)>>()
    }
    """,
    opt_term: ~R"""
    fn opt_term<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> Option<Term<'a>> {
        opts.iter()
            .find_map(|(atom, term)| if *atom == key { Some(*term) } else { None })
    }
    """,
    opt_f32: ~R"""
    fn opt_f32<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> NifResult<f32> {
        opt_f32_default(opts, key, f32::NAN).and_then(|value| {
            if value.is_nan() {
                Err(rustler::Error::BadArg)
            } else {
                Ok(value)
            }
        })
    }
    """,
    opt_f32_option: ~R"""
    fn opt_f32_option<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> NifResult<Option<f32>> {
        match opt_term(opts, key) {
            Some(term) => Ok(Some(term.decode::<f64>()? as f32)),
            None => Ok(None),
        }
    }
    """,
    opt_f32_default: ~R"""
    fn opt_f32_default<'a>(opts: &[(Atom, Term<'a>)], key: Atom, default: f32) -> NifResult<f32> {
        match opt_term(opts, key) {
            Some(term) => Ok(term.decode::<f64>()? as f32),
            None => Ok(default),
        }
    }
    """,
    opt_bool_option: ~R"""
    fn opt_bool_option<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> NifResult<Option<bool>> {
        match opt_term(opts, key) {
            Some(term) => Ok(Some(term.decode::<bool>()?)),
            None => Ok(None),
        }
    }
    """,
    opt_atom_option: ~R"""
    fn opt_atom_option<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> NifResult<Option<Atom>> {
        match opt_term(opts, key) {
            Some(term) => Ok(Some(term.decode::<Atom>()?)),
            None => Ok(None),
        }
    }
    """
  }

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    opts
    |> names()
    |> Enum.map(fn name ->
      @templates
      |> Map.fetch!(name)
      |> RustQ.render!("rustler_opts_helper.rs",
        bind: [key: Rust.expr(Keyword.get(opts, :key, "atoms::opts()"))]
      )
      |> Rust.item()
    end)
  end

  defp names(opts), do: HelperSelection.names(opts, @names)
end
