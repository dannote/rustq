defmodule RustQ.NativeCodegen.GeneratedASTTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST

  test "generates parseable AST support" do
    source = RustQ.NativeCodegen.generated_ast_support()

    assert {:ok, _template} = RustQ.parse(source, "generated_ast.rs")
  end

  test "generated modules are AST-backed" do
    modules = RustQ.NativeCodegen.Modules.asts()

    assert %AST.Module{name: :atoms, items: [%AST.MacroItem{}], vis: :crate} =
             Enum.find(modules, &match?(%AST.Module{name: :atoms}, &1))

    assert %AST.Module{name: :ast_modules, items: constants, vis: :crate} =
             Enum.find(modules, &match?(%AST.Module{name: :ast_modules}, &1))

    constant_names = constants |> Enum.map(& &1.name) |> MapSet.new()
    assert MapSet.member?(constant_names, :FUNCTION)
    refute MapSet.member?(constant_names, :ARM)
    refute MapSet.member?(constant_names, :STRUCT_FIELD)
    refute MapSet.member?(constant_names, :ENUM_VARIANT)
  end

  test "dispatch functions are AST-backed" do
    dispatch = RustQ.NativeCodegen.Dispatch.asts()
    names = dispatch |> Enum.map(& &1.name) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new([
               :decode_ast_item,
               :decode_ast_type,
               :decode_ast_pat,
               :decode_ast_stmt,
               :decode_ast_expr
             ]),
             names
           )

    for function <- dispatch do
      assert %AST.Function{body: [%AST.Return{expr: %AST.Match{}}]} = function
    end
  end

  test "dogfooded decoder modules cover generated decoder categories" do
    decoder_names =
      RustQ.NativeCodegen.Decoders.asts()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    expected_expr_decoders =
      RustQ.Rust.AST.Schema.nodes(:expr)
      |> Enum.map(&String.to_atom("decode_expr_#{&1.name}"))

    expected_stmt_decoders =
      RustQ.Rust.AST.Schema.nodes(:stmt)
      |> Enum.map(&String.to_atom("decode_stmt_#{&1.name}"))

    expected_pat_decoders =
      RustQ.Rust.AST.Schema.nodes(:pat)
      |> Enum.reject(&(&1.name == :pat_atom_guard))
      |> Enum.map(&String.to_atom("decode_#{&1.name}"))

    expected_type_decoders = [
      :decode_type_path,
      :decode_type_unit,
      :decode_type_option,
      :decode_type_result,
      :decode_type_nif_result,
      :decode_type_vec
    ]

    expected_item_decoders = [
      :decode_ast_use,
      :decode_ast_module,
      :decode_ast_const,
      :decode_ast_function,
      :decode_ast_struct,
      :decode_ast_macro_item,
      :decode_ast_enum,
      :decode_struct_field,
      :decode_enum_variant
    ]

    for decoder <-
          expected_item_decoders ++
            expected_type_decoders ++
            expected_expr_decoders ++ expected_stmt_decoders ++ expected_pat_decoders do
      assert MapSet.member?(decoder_names, decoder), "missing dogfooded decoder #{decoder}"
    end
  end
end
