defmodule RustQ.NativeCodegen.Decoders.Expr do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_expr_var(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    raw_expr!("#ident")
  end

  @spec decode_expr_path(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_path(term) do
    parts = unwrap!(Super.path_parts(unwrap!(required_field(term, "parts"))))
    Super.parse_expr(ref(parts))
  end

  @spec decode_expr_atom_value(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_atom_value(term) do
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    expr!(atom_value(name))
  end

  @spec decode_expr_field(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_field(term) do
    receiver = unwrap!(Super.decode_expr(unwrap!(required_field(term, "receiver"))))
    field = Super.format_ident_value(unwrap!(atom_key(term, "field")))
    expr!(field(receiver, field))
  end

  @spec decode_expr_path_call(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_path_call(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    args = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "args"))))
    expr!(path_call(path, args))
  end

  @spec decode_expr_method_call(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_method_call(term) do
    receiver = unwrap!(Super.decode_expr(unwrap!(required_field(term, "receiver"))))
    method = Super.format_ident_value(unwrap!(atom_key(term, "method")))
    args = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "args"))))
    expr!(method_call(receiver, method, args))
  end

  @spec decode_expr_local_call(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_local_call(term) do
    name = unwrap!(atom_key(term, "name"))
    args = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "args"))))
    Super.parse_local_call(name, args)
  end

  @spec decode_expr_ref(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_ref(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())

    if mutable do
      expr!(mut_ref(expr))
    else
      expr!(ref(expr))
    end
  end

  @spec decode_expr_struct_literal(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_struct_literal(term) do
    path = unwrap!(Super.decode_expr(unwrap!(required_field(term, "path"))))
    fields = unwrap!(Super.decode_struct_literal_fields(unwrap!(required_field(term, "fields"))))
    expr!(struct_literal(path, fields))
  end

  @spec decode_expr_nif_raise_atom(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_nif_raise_atom(term) do
    name = unwrap!(atom_key(term, "name"))
    expr!(raise_atom(name))
  end

  @spec decode_expr_binary_op(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_binary_op(term) do
    left = unwrap!(Super.decode_expr(unwrap!(required_field(term, "left"))))
    right = unwrap!(Super.decode_expr(unwrap!(required_field(term, "right"))))
    op = unwrap!(atom_key(term, "op"))

    case op.as_str() do
      "eq" -> expr!(binary(left, :eq, right))
      "and" -> expr!(binary(left, :and, right))
      "or" -> expr!(binary(left, :or, right))
      _ -> err(badarg())
    end
  end

  @spec decode_expr_match(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_match(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    arms = unwrap!(Super.decode_arm_list(unwrap!(required_field(term, "arms"))))
    expr!(match(expr, arms))
  end

  @spec decode_expr_if(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_if(term) do
    condition = unwrap!(Super.decode_expr(unwrap!(required_field(term, "condition"))))
    then_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "then"))))
    else_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "else"))))
    expr!(if_else(condition, then_block, else_block))
  end

  @spec decode_expr_tuple(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_tuple(term) do
    values = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "values"))))
    expr!(tuple(values))
  end

  @spec decode_expr_token_macro(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_token_macro(term) do
    path =
      unwrap!(
        Super.path_parts(unwrap!(required_field(unwrap!(required_field(term, "path")), "parts")))
      )

    tokens = unwrap!(Super.string_field(term, "tokens"))
    Super.parse_expr(ref(token_macro(:format, "\"{}!({})\", path, tokens")))
  end

  @spec decode_expr_ok(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_ok(term) do
    optional_expr = unwrap!(Super.decode_optional_expr_field(term, "expr"))

    case optional_expr do
      nil -> expr!(:ok)
      expr -> expr!({:ok, expr})
    end
  end

  @spec decode_expr_none(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_none(_term) do
    expr!(nil)
  end

  @spec decode_expr_literal(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_literal(term) do
    Super.decode_literal_expr(unwrap!(required_field(term, "value")))
  end

  @spec decode_expr_try(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_try(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    expr!(unwrap!(expr))
  end

  @spec decode_expr_some(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_some(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    expr!(some(expr))
  end

  @spec decode_expr_err(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_err(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    expr!(err(expr))
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
