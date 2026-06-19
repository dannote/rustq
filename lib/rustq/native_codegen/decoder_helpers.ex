defmodule RustQ.NativeCodegen.DecoderHelpers do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec required_expr(term(), R.str()) :: R.nif_result(Expr.t())
  defrust required_expr(term, key) do
    Super.decode_expr(unwrap!(required_field(term, key)))
  end

  @spec required_expr_list(term(), R.str()) :: R.nif_result(R.vec(Expr.t()))
  defrust required_expr_list(term, key) do
    Super.decode_expr_list(unwrap!(required_field(term, key)))
  end

  @spec required_type(term(), R.str()) :: R.nif_result(Type.t())
  defrust required_type(term, key) do
    Super.decode_type(unwrap!(required_field(term, key)))
  end

  @spec required_path(term(), R.str()) :: R.nif_result(Path.t())
  defrust required_path(term, key) do
    Super.parse_ast_path(unwrap!(required_field(term, key)))
  end

  @spec required_string_list(term(), R.str()) :: R.nif_result(R.vec(String.t()))
  defrust required_string_list(term, key) do
    Super.decode_string_list(unwrap!(required_field(term, key)))
  end

  @spec required_type_list(term(), R.str()) :: R.nif_result(R.vec(Type.t()))
  defrust required_type_list(term, key) do
    Super.decode_type_list(unwrap!(required_field(term, key)))
  end

  @spec required_pat(term(), R.str()) :: R.nif_result(Pat.t())
  defrust required_pat(term, key) do
    Super.decode_pat(unwrap!(required_field(term, key)))
  end

  @spec required_pat_list(term(), R.str()) :: R.nif_result(R.vec(Pat.t()))
  defrust required_pat_list(term, key) do
    Super.decode_pat_list(unwrap!(required_field(term, key)))
  end

  @spec required_arm_list(term(), R.str()) :: R.nif_result(R.vec(Arm.t()))
  defrust required_arm_list(term, key) do
    Super.decode_arm_list(unwrap!(required_field(term, key)))
  end

  @spec required_stmt_list(term(), R.str()) :: R.nif_result(R.vec(Stmt.t()))
  defrust required_stmt_list(term, key) do
    Super.decode_stmt_list(unwrap!(required_field(term, key)))
  end

  @spec required_item_list(term(), R.str()) :: R.nif_result(R.vec(Item.t()))
  defrust required_item_list(term, key) do
    Super.decode_item_list(unwrap!(required_field(term, key)))
  end

  @spec required_function_arg_list(term(), R.str()) :: R.nif_result(R.vec(FnArg.t()))
  defrust required_function_arg_list(term, key) do
    Super.decode_function_arg_list(unwrap!(required_field(term, key)))
  end

  @spec required_struct_field_list(term(), R.str()) :: R.nif_result(R.vec(Field.t()))
  defrust required_struct_field_list(term, key) do
    Super.decode_struct_field_list(unwrap!(required_field(term, key)))
  end

  @spec required_enum_variant_list(term(), R.str()) :: R.nif_result(R.vec(Variant.t()))
  defrust required_enum_variant_list(term, key) do
    Super.decode_enum_variant_list(unwrap!(required_field(term, key)))
  end
end
