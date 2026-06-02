defmodule RustQ.Rustler.CachedAtoms do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @helpers_template ~R"""
  fn cached_atom(env: Env, cell: &'static OnceLock<Atom>, name: &str) -> Atom {
      *cell.get_or_init(|| Atom::from_term(name.encode(env)).unwrap())
  }
  """

  @static_template ~R"""
  static __STATIC: OnceLock<Atom> = OnceLock::new();
  """

  @fn_template ~R"""
  fn __fn_name(env: Env) -> Atom {
      cached_atom(env, &__STATIC, __expr_atom_name!())
  }
  """

  @spec build([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) :: [
          Rust.Fragment.t()
        ]
  def build(atoms, opts \\ []) do
    include_helpers? = Keyword.get(opts, :helpers, true)

    atoms = Enum.map(atoms, &atom_spec/1)

    helper_items =
      if include_helpers? do
        [Rust.item(RustQ.render!(@helpers_template, "rustler_cached_atom_helpers.rs"))]
      else
        []
      end

    helper_items ++ Enum.flat_map(atoms, &atom_items/1)
  end

  defp atom_items({name, value}) do
    bindings = [
      STATIC: static_name(name),
      fn_name: "#{name}_atom",
      atom_name: Rust.expr(Rust.literal(value))
    ]

    [
      Rust.item(RustQ.render!(@static_template, "rustler_cached_atom_static.rs", bind: bindings)),
      Rust.item(RustQ.render!(@fn_template, "rustler_cached_atom_fn.rs", bind: bindings))
    ]
  end

  defp atom_spec(name) when is_atom(name), do: {name, Atom.to_string(name)}
  defp atom_spec(name) when is_binary(name), do: {name, name}

  defp atom_spec({name, value}) when (is_atom(name) or is_binary(name)) and is_binary(value),
    do: {name, value}

  defp static_name(name) do
    name
    |> to_string()
    |> Macro.underscore()
    |> String.upcase()
    |> Kernel.<>("_ATOM")
  end
end
