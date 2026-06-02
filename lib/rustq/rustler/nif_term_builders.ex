defmodule RustQ.Rustler.NifTermBuilders do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @names [:map_from_nif_terms, :struct_from_nif_terms]

  @templates %{
    map_from_nif_terms: ~R"""
    fn make_map_from_nif_terms<'a>(
        env: Env<'a>,
        pairs: &[(rustler::wrapper::NIF_TERM, rustler::wrapper::NIF_TERM)],
    ) -> NifResult<Term<'a>> {
        let mut map = unsafe { rustler::wrapper::map::map_new(env.as_c_arg()) };

        for (key, value) in pairs {
            map = unsafe { rustler::wrapper::map::map_put(env.as_c_arg(), map, *key, *value) }
                .ok_or(rustler::Error::BadArg)?;
        }

        Ok(unsafe { Term::new(env, map) })
    }
    """,
    struct_from_nif_terms: ~R"""
    fn make_struct_from_nif_terms<'a>(
        env: Env<'a>,
        keys: &[rustler::wrapper::NIF_TERM],
        values: &[rustler::wrapper::NIF_TERM],
    ) -> NifResult<Term<'a>> {
        if keys.len() != values.len() {
            return Err(rustler::Error::BadArg);
        }

        let mut map = unsafe { rustler::wrapper::map::map_new(env.as_c_arg()) };

        for (key, value) in keys.iter().zip(values.iter()) {
            map = unsafe { rustler::wrapper::map::map_put(env.as_c_arg(), map, *key, *value) }
                .ok_or(rustler::Error::BadArg)?;
        }

        Ok(unsafe { Term::new(env, map) })
    }
    """
  }

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    opts
    |> Keyword.get(:include, @names)
    |> include_names()
    |> Enum.map(&Rust.item(RustQ.render!(template!(&1), "rustler_nif_term_builder.rs")))
  end

  defp include_names(:all), do: @names
  defp include_names(names), do: List.wrap(names)

  defp template!(name), do: Map.fetch!(@templates, name)
end
