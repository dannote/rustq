defmodule RustQ.NativeCodegen.Decoders.Item do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_enum_variant(term()) :: R.nif_result(Variant.t())
  defrust decode_enum_variant(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.EnumVariant"))
    name = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    tuple = unwrap!(Super.decode_type_list(unwrap!(required_field(term, "tuple"))))
    Super.parse_enum_variant(name, tuple)
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
