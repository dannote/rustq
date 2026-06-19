defmodule RustQ.Rustler.Atoms do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST.Builder, as: A

  @spec build([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          Rust.Fragment.t()
  def build(atoms, opts \\ []) do
    item = A.macro_item_call([:rustler, :atoms], atoms)

    case Keyword.get(opts, :module, :atoms) do
      false -> Rust.ast_item(item)
      module -> Rust.ast_item(A.module(module, [item]))
    end
  end
end
