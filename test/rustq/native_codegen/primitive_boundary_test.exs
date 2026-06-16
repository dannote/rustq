defmodule RustQ.NativeCodegen.PrimitiveBoundaryTest do
  use ExUnit.Case, async: true

  @native_dir Path.expand("../../../native/rustq_nif/src", __DIR__)

  test "native primitive bridge is split by responsibility" do
    assert_functions("parse.rs", [
      "parse_syn",
      "parse_type",
      "parse_path",
      "parse_expr"
    ])

    assert_functions("parse_item.rs", [
      "parse_item_use",
      "parse_item_module",
      "parse_item_const",
      "parse_macro_item",
      "parse_item_function",
      "parse_item_struct",
      "parse_struct_field",
      "parse_item_enum",
      "parse_enum_variant"
    ])

    assert_functions("parse_type.rs", [
      "parse_type_path",
      "parse_type_ref"
    ])

    assert_functions("template.rs", [
      "template_error",
      "render_source"
    ])
  end

  test "decode bridge keeps term decoding separate from parse assembly" do
    decode_source = File.read!(Path.join(@native_dir, "decode.rs"))

    refute decode_source =~ ~r/pub\(crate\) fn parse_(item|type|enum|struct|macro)/

    assert_functions("decode.rs", [
      "decode_list",
      "decode_optional_field",
      "decode_literal_expr",
      "decode_pat_literal_value",
      "decode_named_field_list",
      "decode_struct_literal_fields",
      "decode_pat_struct_fields",
      "keyword_args",
      "path_parts",
      "decode_lifetime_list"
    ])
  end

  defp assert_functions(file, expected) do
    source = File.read!(Path.join(@native_dir, file))

    public_functions =
      Regex.scan(~r/pub\(crate\) fn ([a-zA-Z0-9_]+)/, source, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()

    for name <- expected do
      assert name in public_functions, "expected #{file} to define #{name}/..."
    end
  end
end
