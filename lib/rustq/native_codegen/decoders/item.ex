defmodule RustQ.NativeCodegen.Decoders.Item do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec decode_ast_use(term()) :: R.nif_result(ItemUse.t())
  defrust decode_ast_use(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Use"))
    parts = unwrap!(required_field(term, "parts"))

    if unwrap!(is_nil(parts)) do
      group = unwrap!(required_field(term, "group"))

      if unwrap!(is_nil(group)) do
        tree = unwrap!(Super.string_field(term, "tree"))
        Super.parse_item_use(tree)
      else
        Super.parse_item_use_group_term(group)
      end
    else
      parts = unwrap!(Super.decode_string_list(parts))
      Super.parse_item_use_path(parts)
    end
  end

  @spec decode_ast_module(term()) :: R.nif_result(ItemMod.t())
  defrust decode_ast_module(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Module"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    items = unwrap!(required_item_list(term, "items"))
    Super.parse_item_module(name, vis, items)
  end

  @spec decode_ast_impl(term()) :: R.nif_result(ItemImpl.t())
  defrust decode_ast_impl(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Impl"))
    target = unwrap!(required_type(term, "target"))
    trait_path = unwrap!(Super.decode_optional_type_field(term, "trait"))
    impl_items = unwrap!(required_item_list(term, "items"))
    attrs = unwrap!(Super.decode_attribute_list(unwrap!(required_field(term, "attrs"))))
    lifetimes = unwrap!(Super.decode_lifetime_list(unwrap!(required_field(term, "lifetimes"))))
    Super.parse_item_impl(target, trait_path, impl_items, attrs, lifetimes)
  end

  @spec decode_ast_const(term()) :: R.nif_result(ItemConst.t())
  defrust decode_ast_const(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Const"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(required_type(term, "type"))
    expr = unwrap!(required_expr(term, "expr"))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_item_const(name, ty, expr, vis)
  end

  @spec decode_ast_type_alias(term()) :: R.nif_result(ItemType.t())
  defrust decode_ast_type_alias(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.TypeAlias"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(required_type(term, "type"))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_item_type(name, ty, vis)
  end

  @spec decode_ast_static(term()) :: R.nif_result(ItemStatic.t())
  defrust decode_ast_static(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Static"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(required_type(term, "type"))
    expr = unwrap!(required_expr(term, "expr"))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_item_static(name, ty, expr, mutable, vis)
  end

  @spec decode_ast_function(term()) :: R.nif_result(ItemFn.t())
  defrust decode_ast_function(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Function"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    args = unwrap!(required_function_arg_list(term, "args"))
    returns = unwrap!(required_type(term, "returns"))
    lifetime = unwrap!(optional_atom_key(term, "lifetime"))
    stmts = unwrap!(required_stmt_list(term, "body"))
    attrs = unwrap!(Super.decode_attribute_list(unwrap!(required_field(term, "attrs"))))
    Super.parse_item_function_args(name, vis, args, returns, lifetime, stmts, attrs)
  end

  @spec decode_derive_path_list(term()) :: R.nif_result(R.vec(Path.t()))
  defrust decode_derive_path_list(term) do
    terms = unwrap!(Super.decode_derive_path_terms(term))

    Enum.map(terms, fn derive_path ->
      Super.decode_path_value(derive_path)
    end)
  end

  @spec decode_ast_struct(term()) :: R.nif_result(ItemStruct.t())
  defrust decode_ast_struct(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Struct"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    derive = unwrap!(Super.decode_derive(unwrap!(required_field(term, "derive"))))
    lifetime = unwrap!(optional_atom_key(term, "lifetime"))
    fields = unwrap!(required_struct_field_list(term, "fields"))
    attrs = unwrap!(Super.decode_attribute_list(unwrap!(required_field(term, "attrs"))))
    Super.parse_item_struct(name, vis, derive, lifetime, fields, attrs)
  end

  @spec decode_ast_macro_item(term()) :: R.nif_result(Item.t())
  defrust decode_ast_macro_item(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.MacroItem"))
    source = unwrap!(Super.string_field(term, "source"))
    Super.parse_macro_item(source)
  end

  @spec decode_ast_macro_item_call(term()) :: R.nif_result(Item.t())
  defrust decode_ast_macro_item_call(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.MacroItemCall"))
    path = unwrap!(required_path(term, "path"))
    args = unwrap!(Super.decode_macro_item_arg_list(unwrap!(required_field(term, "args"))))
    Super.parse_macro_item_call(path, args)
  end

  @spec decode_ast_enum(term()) :: R.nif_result(ItemEnum.t())
  defrust decode_ast_enum(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Enum"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    derive = unwrap!(Super.decode_derive(unwrap!(required_field(term, "derive"))))
    variants = unwrap!(required_enum_variant_list(term, "variants"))
    attrs = unwrap!(Super.decode_attribute_list(unwrap!(required_field(term, "attrs"))))
    Super.parse_item_enum(name, vis, derive, variants, attrs)
  end

  @spec decode_function_arg(term()) :: R.nif_result(FnArg.t())
  defrust decode_function_arg(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.FunctionArg"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(required_type(term, "type"))
    Super.parse_function_arg(name, ty)
  end

  @spec decode_struct_field(term()) :: R.nif_result(Field.t())
  defrust decode_struct_field(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.StructField"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(required_type(term, "type"))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_struct_field(name, ty, vis)
  end

  @spec decode_enum_variant(term()) :: R.nif_result(Variant.t())
  defrust decode_enum_variant(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.EnumVariant"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    tuple = unwrap!(required_type_list(term, "tuple"))
    Super.parse_enum_variant(name, tuple)
  end
end
