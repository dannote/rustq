defmodule RustQ.NativeCodegen.Decoders do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_pat_var(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    quote_pat!("#ident")
  end

  @spec decode_pat_wildcard(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_wildcard(_term) do
    quote_pat!("_")
  end

  @spec decode_pat_none(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_none(_term) do
    quote_pat!("None")
  end

  @spec decode_pat_path(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_path(term) do
    parts = unwrap!(Super.path_parts(unwrap!(required_field(term, "parts"))))
    path = unwrap!(Super.parse_path(ref(parts)))
    quote_pat!("#path")
  end

  @spec decode_pat_literal(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_literal(term) do
    Super.decode_pat_literal_value(unwrap!(required_field(term, "value")))
  end

  @spec decode_pat_some(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_some(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    quote_pat!("Some(#pat)")
  end

  @spec decode_pat_ok(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_ok(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    quote_pat!("Ok(#pat)")
  end

  @spec decode_pat_err(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_err(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    quote_pat!("Err(#pat)")
  end

  @spec decode_stmt_expr_stmt(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_expr_stmt(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_stmt!("#expr;")
  end

  @spec decode_stmt_return(term()) :: R.nif_result(Stmt.t())
  defrust decode_stmt_return(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    {:ok, Stmt.expr(expr, none())}
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

  @spec decode_arm(term()) :: R.nif_result(Arm.t())
  defrust decode_arm(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Arm"))
    pat_term = unwrap!(required_field(term, "pattern"))
    block = unwrap!(Super.decode_block(unwrap!(required_field(term, "body"))))

    if unwrap!(struct_name(pat_term)) == "Elixir.RustQ.Rust.AST.PatAtomGuard" do
      Super.decode_atom_guard_arm(pat_term, block)
    else
      pat = unwrap!(Super.decode_pat(pat_term))
      quote_arm!("#pat => #block,")
    end
  end

  @spec decode_expr_var(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    quote_expr!("#ident")
  end

  @spec decode_expr_path(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_path(term) do
    parts = unwrap!(Super.path_parts(unwrap!(required_field(term, "parts"))))
    Super.parse_expr(ref(parts))
  end

  @spec decode_expr_atom_value(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_atom_value(term) do
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    quote_expr!("atoms::#name()")
  end

  @spec decode_expr_field(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_field(term) do
    receiver = unwrap!(Super.decode_expr(unwrap!(required_field(term, "receiver"))))
    field = Super.format_ident_value(unwrap!(atom_key(term, "field")))
    quote_expr!("#receiver.#field")
  end

  @spec decode_expr_path_call(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_path_call(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    args = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "args"))))
    quote_expr!("#path(#(#args),*)")
  end

  @spec decode_expr_method_call(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_method_call(term) do
    receiver = unwrap!(Super.decode_expr(unwrap!(required_field(term, "receiver"))))
    method = Super.format_ident_value(unwrap!(atom_key(term, "method")))
    args = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "args"))))
    quote_expr!("#receiver.#method(#(#args),*)")
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
      quote_expr!("&mut #expr")
    else
      quote_expr!("&#expr")
    end
  end

  @spec decode_pat_tuple(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_tuple(term) do
    patterns = unwrap!(Super.decode_pat_list(unwrap!(required_field(term, "patterns"))))
    quote_pat!("(#(#patterns),*)")
  end

  @spec decode_pat_path_tuple(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_path_tuple(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    patterns = unwrap!(Super.decode_pat_list(unwrap!(required_field(term, "patterns"))))
    quote_pat!("#path(#(#patterns),*)")
  end

  @spec decode_pat_struct(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_struct(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    fields = unwrap!(Super.decode_pat_struct_fields(unwrap!(required_field(term, "fields"))))
    quote_pat!("#path { #(#fields),* }")
  end

  @spec decode_expr_struct_literal(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_struct_literal(term) do
    path = unwrap!(Super.decode_expr(unwrap!(required_field(term, "path"))))
    fields = unwrap!(Super.decode_struct_literal_fields(unwrap!(required_field(term, "fields"))))
    quote_expr!("#path { #(#fields),* }")
  end

  @spec decode_expr_nif_raise_atom(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_nif_raise_atom(term) do
    name = unwrap!(atom_key(term, "name"))
    quote_expr!("rustler::Error::RaiseAtom(#name)")
  end

  @spec decode_expr_binary_op(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_binary_op(term) do
    left = unwrap!(Super.decode_expr(unwrap!(required_field(term, "left"))))
    right = unwrap!(Super.decode_expr(unwrap!(required_field(term, "right"))))
    op = unwrap!(atom_key(term, "op"))

    case op.as_str() do
      "eq" -> quote_expr!("#left == #right")
      "and" -> quote_expr!("#left && #right")
      "or" -> quote_expr!("#left || #right")
      _ -> err(badarg())
    end
  end

  @spec decode_expr_match(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_match(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    arms = unwrap!(Super.decode_arm_list(unwrap!(required_field(term, "arms"))))
    quote_expr!("match #expr { #(#arms)* }")
  end

  @spec decode_expr_if(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_if(term) do
    condition = unwrap!(Super.decode_expr(unwrap!(required_field(term, "condition"))))
    then_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "then"))))
    else_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "else"))))
    quote_expr!("if #condition #then_block else #else_block")
  end

  @spec decode_expr_tuple(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_tuple(term) do
    values = unwrap!(Super.decode_expr_list(unwrap!(required_field(term, "values"))))
    quote_expr!("(#(#values),*)")
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

  @spec decode_expr_none(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_none(_term) do
    quote_expr!("None")
  end

  @spec decode_expr_literal(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_literal(term) do
    Super.decode_literal_expr(unwrap!(required_field(term, "value")))
  end

  @spec decode_expr_try(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_try(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_expr!("#expr?")
  end

  @spec decode_expr_some(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_some(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_expr!("Some(#expr)")
  end

  @spec decode_expr_err(term()) :: R.nif_result(Expr.t())
  defrust decode_expr_err(term) do
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    quote_expr!("Err(#expr)")
  end

  def asts do
    Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
  end
end
