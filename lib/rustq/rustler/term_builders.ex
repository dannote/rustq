defmodule RustQ.Rustler.TermBuilders do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @names [:map_from_terms, :struct_from_terms]

  @templates %{
    map_from_terms: ~R"""
    fn make_map_from_terms<'a>(
        env: Env<'a>,
        pairs: &[(Term<'a>, Term<'a>)],
    ) -> NifResult<Term<'a>> {
        let (keys, values): (Vec<_>, Vec<_>) = pairs.iter().copied().unzip();
        Term::map_from_term_arrays(env, &keys, &values)
    }
    """,
    struct_from_terms: ~R"""
    fn make_struct_from_terms<'a>(
        env: Env<'a>,
        keys: &[Term<'a>],
        values: &[Term<'a>],
    ) -> NifResult<Term<'a>> {
        Term::map_from_term_arrays(env, keys, values)
    }
    """
  }

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    opts
    |> Keyword.get(:include, @names)
    |> include_names()
    |> Enum.map(&Rust.item(RustQ.render!(template!(&1), "rustler_term_builder.rs")))
  end

  defp include_names(:all), do: @names
  defp include_names(names), do: List.wrap(names)

  defp template!(name), do: Map.fetch!(@templates, name)
end
