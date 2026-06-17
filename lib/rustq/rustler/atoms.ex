defmodule RustQ.Rustler.Atoms do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A

  @spec build([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          Rust.Fragment.t()
  def build(atoms, opts \\ []) do
    item = A.macro_item_call([:rustler, :atoms], atoms)

    case Keyword.get(opts, :module, :atoms) do
      false -> rust_item(item)
      module -> rust_item(A.module(module, [item]))
    end
  end

  defp rust_item(ast), do: Rust.item(RustQ.Rust.AST.Render.render_item_native(ast))
end
