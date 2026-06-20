defmodule RustQ.Codegen.Decoders do
  @moduledoc false

  alias RustQ.Codegen.Decoders.{Arm, Expr, Item, Pat, Stmt, Type}

  def asts do
    [
      Item.asts(),
      Type.asts(),
      Pat.asts(),
      Stmt.asts(),
      Arm.asts(),
      Expr.asts()
    ]
    |> List.flatten()
  end
end
