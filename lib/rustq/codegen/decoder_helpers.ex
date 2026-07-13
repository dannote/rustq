defmodule RustQ.Codegen.DecoderHelpers do
  @moduledoc false

  use RustQ.Codegen.DefrustModule,
    callable_modules: [RustQ.Codegen.Helpers],
    rust_sources: ["native/rustq_nif/src/decode.rs"]

  @spec required_expr(term(), R.str()) :: R.nif_result(R.path(:Expr))
  defrust required_expr(term, key) do
    Super.decode_expr(required_field(term, key))
  end

  @spec required_expr_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Expr)))
  defrust required_expr_list(term, key) do
    Super.decode_expr_list(required_field(term, key))
  end

  @spec required_type(term(), R.str()) :: R.nif_result(R.path(:Type))
  defrust required_type(term, key) do
    Super.decode_type(required_field(term, key))
  end

  @spec required_path(term(), R.str()) :: R.nif_result(Path.t())
  defrust required_path(term, key) do
    Super.parse_ast_path(required_field(term, key))
  end

  @spec required_string_list(term(), R.str()) :: R.nif_result(R.vec(String.t()))
  defrust required_string_list(term, key) do
    Super.decode_string_list(required_field(term, key))
  end

  @spec required_type_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Type)))
  defrust required_type_list(term, key) do
    Super.decode_type_list(required_field(term, key))
  end

  @spec required_pat(term(), R.str()) :: R.nif_result(R.path(:Pat))
  defrust required_pat(term, key) do
    Super.decode_pat(required_field(term, key))
  end

  @spec required_pat_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Pat)))
  defrust required_pat_list(term, key) do
    Super.decode_pat_list(required_field(term, key))
  end

  @spec required_arm_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Arm)))
  defrust required_arm_list(term, key) do
    Super.decode_arm_list(required_field(term, key))
  end

  @spec required_stmt_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Stmt)))
  defrust required_stmt_list(term, key) do
    Super.decode_stmt_list(required_field(term, key))
  end

  @spec required_item_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Item)))
  defrust required_item_list(term, key) do
    Super.decode_item_list(required_field(term, key))
  end

  @spec required_function_arg_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:FnArg)))
  defrust required_function_arg_list(term, key) do
    Super.decode_function_arg_list(required_field(term, key))
  end

  @spec required_struct_field_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Field)))
  defrust required_struct_field_list(term, key) do
    Super.decode_struct_field_list(required_field(term, key))
  end

  @spec required_enum_variant_list(term(), R.str()) :: R.nif_result(R.vec(R.path(:Variant)))
  defrust required_enum_variant_list(term, key) do
    Super.decode_enum_variant_list(required_field(term, key))
  end
end
