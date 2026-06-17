defmodule RustQ.Rustler.CachedAtoms do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [function: 3, static: 3]

  require A
  require I

  @helpers_template ~R"""
  fn cached_atom(env: Env, cell: &'static OnceLock<Atom>, name: &str) -> Atom {
      *cell.get_or_init(|| Atom::from_term(name.encode(env)).unwrap())
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
    static_name = static_name(name)

    [
      rust_item(
        static(String.to_atom(static_name), "OnceLock<Atom>", A.path_call([:OnceLock, :new]))
      ),
      rust_item(
        function String.to_atom("#{name}_atom"), args: [env: "Env"], returns: "Atom" do
          A.return(
            A.call(:cached_atom, [
              A.var(:env),
              A.ref(A.var(String.to_atom(static_name))),
              A.lit(value)
            ])
          )
        end
      )
    ]
  end

  defp atom_spec(name) when is_atom(name), do: {name, Atom.to_string(name)}
  defp atom_spec(name) when is_binary(name), do: {name, name}

  defp atom_spec({name, value}) when (is_atom(name) or is_binary(name)) and is_binary(value),
    do: {name, value}

  defp rust_item(ast), do: Rust.item(RustQ.Rust.AST.Render.render_item(ast))

  defp static_name(name) do
    name
    |> to_string()
    |> Macro.underscore()
    |> String.upcase()
    |> Kernel.<>("_ATOM")
  end
end
