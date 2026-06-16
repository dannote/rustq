defmodule RustQ.NativeCodegen.Decoders do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_pat_var(term()) :: R.nif_result(R.pat())
  defrust decode_pat_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    quote_pat!("#ident")
  end

  @spec decode_pat_wildcard(term()) :: R.nif_result(R.pat())
  defrust decode_pat_wildcard(_term) do
    quote_pat!("_")
  end

  @spec decode_pat_none(term()) :: R.nif_result(R.pat())
  defrust decode_pat_none(_term) do
    quote_pat!("None")
  end

  @spec decode_pat_path(term()) :: R.nif_result(R.pat())
  defrust decode_pat_path(term) do
    parts = unwrap!(Super.path_parts(unwrap!(required_field(term, "parts"))))
    path = unwrap!(Super.parse_path(ref(parts)))
    quote_pat!("#path")
  end

  @spec decode_pat_literal(term()) :: R.nif_result(R.pat())
  defrust decode_pat_literal(term) do
    Super.decode_pat_literal_value(unwrap!(required_field(term, "value")))
  end

  @spec decode_pat_some(term()) :: R.nif_result(R.pat())
  defrust decode_pat_some(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    quote_pat!("Some(#pat)")
  end

  @spec decode_pat_ok(term()) :: R.nif_result(R.pat())
  defrust decode_pat_ok(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    quote_pat!("Ok(#pat)")
  end

  @spec decode_pat_err(term()) :: R.nif_result(R.pat())
  defrust decode_pat_err(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    quote_pat!("Err(#pat)")
  end

  @spec decode_stmt_expr_stmt(term()) :: R.nif_result(R.stmt())
  defrust decode_stmt_expr_stmt(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_stmt!("#expr;")
  end

  @spec decode_stmt_return(term()) :: R.nif_result(R.stmt())
  defrust decode_stmt_return(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    {:ok, Stmt.expr(expr, none())}
  end

  @spec decode_expr_var(term()) :: R.nif_result(R.expr())
  defrust decode_expr_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    quote_expr!("#ident")
  end

  @spec decode_expr_path(term()) :: R.nif_result(R.expr())
  defrust decode_expr_path(term) do
    parts = unwrap!(Super.path_parts(unwrap!(required_field(term, "parts"))))
    Super.parse_expr(ref(parts))
  end

  @spec decode_expr_atom_value(term()) :: R.nif_result(R.expr())
  defrust decode_expr_atom_value(term) do
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    quote_expr!("atoms::#name()")
  end

  @spec decode_expr_none(term()) :: R.nif_result(R.expr())
  defrust decode_expr_none(_term) do
    quote_expr!("None")
  end

  @spec decode_expr_literal(term()) :: R.nif_result(R.expr())
  defrust decode_expr_literal(term) do
    Super.decode_literal_expr(unwrap!(required_field(term, "value")))
  end

  @spec decode_expr_try(term()) :: R.nif_result(R.expr())
  defrust decode_expr_try(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_expr!("#expr?")
  end

  @spec decode_expr_some(term()) :: R.nif_result(R.expr())
  defrust decode_expr_some(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_expr!("Some(#expr)")
  end

  @spec decode_expr_err(term()) :: R.nif_result(R.expr())
  defrust decode_expr_err(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_expr!("Err(#expr)")
  end

  def asts do
    Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
  end
end
