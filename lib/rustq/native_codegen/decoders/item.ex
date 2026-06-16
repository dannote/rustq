defmodule RustQ.NativeCodegen.Decoders.Item do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_ast_use(term()) :: R.nif_result(ItemUse.t())
  defrust decode_ast_use(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Use"))
    tree = unwrap!(Super.string_field(term, "tree"))
    Super.parse_item_use(tree)
  end

  @spec decode_ast_module(term()) :: R.nif_result(ItemMod.t())
  defrust decode_ast_module(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Module"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    items = unwrap!(Super.decode_item_list(unwrap!(required_field(term, "items"))))
    Super.parse_item_module(name, vis, items)
  end

  @spec decode_ast_const(term()) :: R.nif_result(ItemConst.t())
  defrust decode_ast_const(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Const"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(Super.decode_type(unwrap!(required_field(term, "type"))))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_item_const(name, ty, expr, vis)
  end

  @spec decode_ast_function(term()) :: R.nif_result(ItemFn.t())
  defrust decode_ast_function(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Function"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    args = unwrap!(Super.decode_function_arg_list(unwrap!(required_field(term, "args"))))
    returns = unwrap!(Super.decode_type(unwrap!(required_field(term, "returns"))))
    lifetime = unwrap!(optional_atom_key(term, "lifetime"))
    stmts = unwrap!(Super.decode_stmt_list(unwrap!(required_field(term, "body"))))
    Super.parse_item_function_args(name, vis, args, returns, lifetime, stmts)
  end

  @spec decode_ast_struct(term()) :: R.nif_result(ItemStruct.t())
  defrust decode_ast_struct(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Struct"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    derive = unwrap!(Super.decode_derive(unwrap!(required_field(term, "derive"))))
    lifetime = unwrap!(optional_atom_key(term, "lifetime"))
    fields = unwrap!(Super.decode_struct_field_list(unwrap!(required_field(term, "fields"))))
    Super.parse_item_struct(name, vis, derive, lifetime, fields)
  end

  @spec decode_ast_macro_item(term()) :: R.nif_result(Item.t())
  defrust decode_ast_macro_item(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.MacroItem"))
    source = unwrap!(Super.string_field(term, "source"))
    Super.parse_macro_item(source)
  end

  @spec decode_ast_enum(term()) :: R.nif_result(ItemEnum.t())
  defrust decode_ast_enum(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Enum"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    derive = unwrap!(Super.decode_derive(unwrap!(required_field(term, "derive"))))
    variants = unwrap!(Super.decode_enum_variant_list(unwrap!(required_field(term, "variants"))))
    Super.parse_item_enum(name, vis, derive, variants)
  end

  @spec decode_function_arg(term()) :: R.nif_result(FnArg.t())
  defrust decode_function_arg(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.FunctionArg"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(Super.decode_type(unwrap!(required_field(term, "type"))))
    Super.parse_function_arg(name, ty)
  end

  @spec decode_struct_field(term()) :: R.nif_result(Field.t())
  defrust decode_struct_field(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.StructField"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(Super.decode_type(unwrap!(required_field(term, "type"))))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_struct_field(name, ty, vis)
  end

  @spec decode_enum_variant(term()) :: R.nif_result(Variant.t())
  defrust decode_enum_variant(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.EnumVariant"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    tuple = unwrap!(Super.decode_type_list(unwrap!(required_field(term, "tuple"))))
    Super.parse_enum_variant(name, tuple)
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
