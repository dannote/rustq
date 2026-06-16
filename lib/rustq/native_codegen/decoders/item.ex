defmodule RustQ.NativeCodegen.Decoders.Item do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_ast_const(term()) :: R.nif_result(ItemConst.t())
  defrust decode_ast_const(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Const"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    ty = unwrap!(Super.decode_type(unwrap!(required_field(term, "type"))))
    expr = unwrap!(Super.decode_expr(unwrap!(required_field(term, "expr"))))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    Super.parse_item_const(name, ty, expr, vis)
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

  @spec decode_ast_enum(term()) :: R.nif_result(ItemEnum.t())
  defrust decode_ast_enum(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Enum"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    vis = unwrap!(Super.decode_vis(unwrap!(required_field(term, "vis"))))
    derive = unwrap!(Super.decode_derive(unwrap!(required_field(term, "derive"))))
    variants = unwrap!(Super.decode_enum_variant_list(unwrap!(required_field(term, "variants"))))
    Super.parse_item_enum(name, vis, derive, variants)
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
