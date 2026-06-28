defmodule RustQ.Meta.Validate do
  @moduledoc """
  Validates generated RustQ AST items by rendering and parsing them as Rust.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render

  def item_ast(%AST.Function{} = item), do: ast_item(item)
  def item_ast(%AST.Module{} = item), do: ast_item(item)
  def item_ast(%AST.MacroItem{} = item), do: ast_item(item)
  def item_ast(%AST.Impl{} = item), do: ast_item(item)
  def item_ast(%AST.Struct{} = item), do: ast_item(item)
  def item_ast(%AST.Enum{} = item), do: ast_item(item)

  def ast_item(item) do
    RustQ.parse_fragment!(:item, Render.render_item(item))
  end
end
