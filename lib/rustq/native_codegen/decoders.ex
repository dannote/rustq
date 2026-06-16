defmodule RustQ.NativeCodegen.Decoders do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_pat_wildcard(term()) :: R.nif_result(R.pat())
  defrust decode_pat_wildcard(_term) do
    quote_pat!("_")
  end

  @spec decode_pat_none(term()) :: R.nif_result(R.pat())
  defrust decode_pat_none(_term) do
    quote_pat!("None")
  end

  @spec decode_pat_literal(term()) :: R.nif_result(R.pat())
  defrust decode_pat_literal(term) do
    Super.decode_pat_literal_value(unwrap!(term.map_get(unwrap!(atom(term.get_env(), "value")))))
  end

  @spec decode_stmt_expr_stmt(term()) :: R.nif_result(R.stmt())
  defrust decode_stmt_expr_stmt(term) do
    expr =
      unwrap!(Super.decode_expr(unwrap!(term.map_get(unwrap!(atom(term.get_env(), "expr"))))))

    quote_stmt!("#expr;")
  end

  @spec decode_stmt_return(term()) :: R.nif_result(R.stmt())
  defrust decode_stmt_return(term) do
    expr =
      unwrap!(Super.decode_expr(unwrap!(term.map_get(unwrap!(atom(term.get_env(), "expr"))))))

    {:ok, Stmt.expr(expr, none())}
  end

  @spec decode_expr_none(term()) :: R.nif_result(R.expr())
  defrust decode_expr_none(_term) do
    quote_expr!("None")
  end

  @spec decode_expr_literal(term()) :: R.nif_result(R.expr())
  defrust decode_expr_literal(term) do
    Super.decode_literal_expr(unwrap!(term.map_get(unwrap!(atom(term.get_env(), "value")))))
  end

  def asts do
    Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
  end
end
