defmodule RustQ.NativeCodegen.Decoders do
  @moduledoc false

  def asts do
    [
      RustQ.NativeCodegen.Decoders.Item.asts(),
      RustQ.NativeCodegen.Decoders.Type.asts(),
      RustQ.NativeCodegen.Decoders.Pat.asts(),
      RustQ.NativeCodegen.Decoders.Stmt.asts(),
      RustQ.NativeCodegen.Decoders.Arm.asts(),
      RustQ.NativeCodegen.Decoders.Expr.asts()
    ]
    |> List.flatten()
  end
end
