defmodule RustQ.NativeCodegen.Decoders.Expr do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec decode_expr_var(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    Super.parse_ident_expr(ident)
  end

  @spec decode_expr_path(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_path(term) do
    path = unwrap!(Super.parse_ast_path(term))
    Super.parse_path_expr(path)
  end

  @spec decode_expr_atom_value(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_atom_value(term) do
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    module = unwrap!(Super.decode_string_list(unwrap!(required_field(term, "module"))))
    Super.parse_atom_value_expr(module, name)
  end

  @spec decode_expr_field(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_field(term) do
    receiver = unwrap!(required_expr(term, "receiver"))
    field = unwrap!(required_field(term, "field"))
    Super.parse_field_expr(receiver, field)
  end

  @spec decode_expr_index(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_index(term) do
    receiver = unwrap!(required_expr(term, "receiver"))
    index = unwrap!(required_expr(term, "index"))
    Super.parse_index_expr(receiver, index)
  end

  @spec decode_expr_range(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_range(term) do
    start = unwrap!(Super.decode_optional_expr_field(term, "start"))
    stop = unwrap!(Super.decode_optional_expr_field(term, "stop"))
    Super.parse_range_expr(start, stop)
  end

  @spec decode_expr_cast(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_cast(term) do
    expr = unwrap!(required_expr(term, "expr"))
    ty = unwrap!(required_type(term, "type"))
    Super.parse_cast_expr(expr, ty)
  end

  @spec decode_expr_unary_op(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_unary_op(term) do
    op = unwrap!(atom_key(term, "op"))
    expr = unwrap!(required_expr(term, "expr"))

    case op.as_str() do
      "not" -> Super.parse_unary_expr(op, expr)
      "neg" -> Super.parse_unary_expr(op, expr)
      "deref" -> Super.parse_unary_expr(op, expr)
      _ -> err(badarg())
    end
  end

  @spec decode_expr_path_call(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_path_call(term) do
    path = unwrap!(required_path(term, "path"))
    args = unwrap!(required_expr_list(term, "args"))
    generics = unwrap!(required_type_list(term, "generics"))
    Super.parse_path_call_expr(path, args, generics)
  end

  @spec decode_expr_method_call(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_method_call(term) do
    receiver = unwrap!(required_expr(term, "receiver"))
    method = Super.format_ident_value(unwrap!(atom_key(term, "method")))
    args = unwrap!(required_expr_list(term, "args"))
    generics = unwrap!(required_type_list(term, "generics"))
    Super.parse_method_call_expr(receiver, method, args, generics)
  end

  @spec decode_expr_local_call(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_local_call(term) do
    name = unwrap!(atom_key(term, "name"))
    args = unwrap!(required_expr_list(term, "args"))
    Super.parse_local_call(name, args)
  end

  @spec decode_expr_ref(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_ref(term) do
    expr = unwrap!(required_expr(term, "expr"))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())

    Super.parse_ref_expr(expr, mutable)
  end

  @spec decode_expr_struct_literal(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_struct_literal(term) do
    path = unwrap!(required_expr(term, "path"))
    fields = unwrap!(Super.decode_struct_literal_fields(unwrap!(required_field(term, "fields"))))
    Super.parse_struct_literal_expr(path, fields)
  end

  @spec decode_expr_nif_raise_atom(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_nif_raise_atom(term) do
    name = unwrap!(atom_key(term, "name"))
    Super.parse_raise_atom_expr(name)
  end

  @spec decode_expr_binary_op(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_binary_op(term) do
    left = unwrap!(required_expr(term, "left"))
    right = unwrap!(required_expr(term, "right"))
    op = unwrap!(atom_key(term, "op"))

    Super.parse_binary_expr(left, op, right)
  end

  @spec decode_expr_match(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_match(term) do
    expr = unwrap!(required_expr(term, "expr"))
    arms = unwrap!(required_arm_list(term, "arms"))
    Super.parse_match_expr(expr, arms)
  end

  @spec decode_expr_if(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_if(term) do
    condition = unwrap!(required_expr(term, "condition"))
    then_block = unwrap!(Super.decode_block(unwrap!(required_field(term, "then"))))
    else_block = unwrap!(Super.decode_optional_block_field(term, "else"))
    Super.parse_if_expr(condition, then_block, else_block)
  end

  @spec decode_expr_tuple(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_tuple(term) do
    values = unwrap!(required_expr_list(term, "values"))
    Super.parse_tuple_expr(values)
  end

  @spec decode_expr_vec_literal(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_vec_literal(term) do
    values = unwrap!(required_expr_list(term, "values"))
    Super.parse_vec_expr(values)
  end

  @spec decode_expr_array_literal(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_array_literal(term) do
    values = unwrap!(required_expr_list(term, "values"))
    Super.parse_array_expr(values)
  end

  @spec decode_expr_closure(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_closure(term) do
    args = unwrap!(Super.decode_ident_list(unwrap!(required_field(term, "args"))))
    body = unwrap!(required_expr(term, "body"))
    Super.parse_closure_expr(args, body)
  end

  @spec decode_expr_macro_call(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_macro_call(term) do
    path = unwrap!(required_path(term, "path"))
    args = unwrap!(required_expr_list(term, "args"))
    Super.parse_macro_call_expr(path, args)
  end

  @spec decode_expr_byte_string(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_byte_string(term) do
    value = unwrap!(Super.string_field(term, "value"))
    Super.parse_byte_string_expr(value)
  end

  @spec decode_expr_escape_expr(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_escape_expr(term) do
    source = unwrap!(Super.string_field(term, "source"))
    Super.parse_expr(ref(source))
  end

  @spec decode_expr_token_macro(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_token_macro(term) do
    path =
      unwrap!(
        Super.path_parts(unwrap!(required_field(unwrap!(required_field(term, "path")), "parts")))
      )

    tokens = unwrap!(Super.string_field(term, "tokens"))
    Super.parse_expr(token_macro(:format, "\"{}!({})\", path, tokens"))
  end

  @spec decode_expr_ok(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_ok(term) do
    optional_expr = unwrap!(Super.decode_optional_expr_field(term, "expr"))

    Super.parse_ok_expr(optional_expr)
  end

  @spec decode_expr_none(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_none(term) do
    Super.parse_none_expr(term)
  end

  @spec decode_expr_literal(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_literal(term) do
    Super.decode_literal_expr(unwrap!(required_field(term, "value")))
  end

  @spec decode_expr_try(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_try(term) do
    expr = unwrap!(required_expr(term, "expr"))
    Super.parse_try_expr(expr)
  end

  @spec decode_expr_some(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_some(term) do
    expr = unwrap!(required_expr(term, "expr"))
    Super.parse_some_expr(expr)
  end

  @spec decode_expr_err(term()) :: R.nif_result(R.path(:Expr))
  defrust decode_expr_err(term) do
    expr = unwrap!(required_expr(term, "expr"))
    Super.parse_err_expr(expr)
  end
end
