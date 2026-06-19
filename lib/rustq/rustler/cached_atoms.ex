defmodule RustQ.Rustler.CachedAtoms do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Rust
  alias RustQ.Type, as: R
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [function: 3, static: 3]

  require A
  require I

  @spec cached_atom(R.path(:Env), R.ref(R.raw(:"OnceLock<Atom>")), R.ref(R.path(:str))) ::
          R.atom()
  defrust cached_atom(env, cell, name) do
    deref(cell.get_or_init(fn -> Atom.from_term(name.encode(env)).unwrap() end))
  end

  @spec build([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) :: [
          Rust.Fragment.t()
        ]
  def build(atoms, opts \\ []) do
    include_helpers? = Keyword.get(opts, :helpers, true)

    atoms = Enum.map(atoms, &atom_spec/1)

    helper_items =
      if include_helpers? do
        [RustQ.Meta.defrust_item(__MODULE__, :cached_atom)]
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
