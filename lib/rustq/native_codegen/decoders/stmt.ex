defmodule RustQ.NativeCodegen.Decoders.Stmt do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec decode_stmt_assign(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_assign(term) do
    target = unwrap!(Super.decode_expr(unwrap!(required_field(term, "target"))))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    Super.parse_assign_stmt(target, expr)
  end

  @spec decode_stmt_expr_stmt(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_expr_stmt(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    stmt!(expr)
  end

  @spec decode_stmt_return(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_return(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    {:ok, Stmt.expr(expr, none())}
  end

  @spec decode_stmt_early_return(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_early_return(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    Super.parse_return_stmt(expr)
  end

  @spec decode_stmt_if_let(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_if_let(term) do
    pattern = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    then_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "then"))))
    else_block = unwrap!(Super.decode_optional_block_field(term, "else"))
    Super.parse_if_let_stmt(pattern, expr, then_block, else_block)
  end

  @spec decode_stmt_for(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_for(term) do
    pattern = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    body = unwrap!(Super.decode_block(unwrap!(required_field(term, "body"))))
    Super.parse_for_stmt(pattern, expr, body)
  end

  @spec decode_stmt_let(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_let(term) do
    pattern = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())
    pat_tokens = unwrap!(Super.decode_let_pattern(pattern, mutable))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    ty = unwrap!(Super.decode_optional_type_field(term, "type"))
    Super.parse_let_stmt(pat_tokens, ty, expr)
  end

  @spec decode_stmt_let_else(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_let_else(term) do
    pattern = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    else_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "else"))))
    Super.parse_let_else_stmt(pattern, expr, else_block)
  end
end
