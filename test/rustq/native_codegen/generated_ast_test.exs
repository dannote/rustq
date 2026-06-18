defmodule RustQ.NativeCodegen.GeneratedASTTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST

  test "generates parseable AST support" do
    source = RustQ.NativeCodegen.generated_ast_support()

    assert {:ok, _template} = RustQ.parse(source, "generated_ast.rs")
  end

  test "generated modules are AST-backed" do
    modules = RustQ.NativeCodegen.Modules.asts()

    assert %AST.Module{name: :atoms, items: [%AST.MacroItemCall{}], vis: :crate} =
             Enum.find(modules, &match?(%AST.Module{name: :atoms}, &1))

    assert %AST.Module{name: :ast_modules, items: constants, vis: :crate} =
             Enum.find(modules, &match?(%AST.Module{name: :ast_modules}, &1))

    constant_names = constants |> Enum.map(& &1.name) |> MapSet.new()
    assert MapSet.member?(constant_names, :FUNCTION)
    refute MapSet.member?(constant_names, :ARM)
    refute MapSet.member?(constant_names, :ATTRIBUTE)
    refute MapSet.member?(constant_names, :DERIVE)
    refute MapSet.member?(constant_names, :FUNCTION_ARG)
    refute MapSet.member?(constant_names, :STRUCT_FIELD)
    refute MapSet.member?(constant_names, :ENUM_VARIANT)

    assert %AST.Function{
             name: :atom,
             vis: :crate,
             args: [
               %AST.FunctionArg{name: :env, type: %AST.TypePath{parts: [:Env]}},
               %AST.FunctionArg{
                 name: :name,
                 type: %AST.TypeRef{inner: %AST.TypePath{parts: [:str]}}
               }
             ],
             returns: %AST.TypeNifResult{inner: %AST.TypePath{parts: [:Atom]}}
           } = Enum.find(List.flatten(modules), &match?(%AST.Function{name: :atom}, &1))
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

  test "type ref decoder delegates only the syn ref construction boundary" do
    assert %AST.Function{body: body} =
             RustQ.NativeCodegen.Decoders.Type.__rustq_asts__()
             |> Enum.find(&(&1.name == :decode_type_ref))

    assert %AST.Return{
             expr: %AST.PathCall{path: %AST.Path{parts: [:super, :parse_type_ref]}}
           } = List.last(body)
  end

  test "type container decoders use generic type construction" do
    decoders = RustQ.NativeCodegen.Decoders.Type.__rustq_asts__()

    for name <- [
          :decode_type_option,
          :decode_type_result,
          :decode_type_nif_result,
          :decode_type_vec
        ] do
      assert %AST.Function{body: body} = Enum.find(decoders, &(&1.name == name))

      assert %AST.Return{
               expr: %AST.PathCall{
                 path: %AST.Path{parts: [:super, :parse_type_generic]},
                 args: [_path, %AST.VecLiteral{}]
               }
             } = List.last(body)
    end
  end

  test "dogfooded type helpers cover path and lifetime list boundaries" do
    type_decoders = RustQ.NativeCodegen.Decoders.Type.__rustq_asts__()

    assert %AST.Function{name: :path_parts, body: path_body} =
             Enum.find(type_decoders, &(&1.name == :path_parts))

    assert %AST.Let{
             expr: %AST.Try{
               expr: %AST.PathCall{path: %AST.Path{parts: [:super, :decode_string_list]}}
             }
           } =
             hd(path_body)

    assert %AST.Return{expr: %AST.Ok{expr: %AST.MethodCall{method: :join}}} = List.last(path_body)

    assert %AST.Function{name: :decode_lifetime_list, body: lifetime_body} =
             Enum.find(type_decoders, &(&1.name == :decode_lifetime_list))

    assert [
             %AST.Return{
               expr: %AST.PathCall{path: %AST.Path{parts: [:super, :decode_string_list]}}
             }
           ] =
             lifetime_body
  end

  test "dogfooded derive decoder uses iterator lowering" do
    item_decoders = RustQ.NativeCodegen.Decoders.Item.__rustq_asts__()

    assert %AST.Function{name: :decode_derive_path_list, body: body} =
             Enum.find(item_decoders, &(&1.name == :decode_derive_path_list))

    assert %AST.Return{
             expr: %AST.MethodCall{
               method: :collect,
               receiver: %AST.MethodCall{
                 method: :map,
                 args: [%AST.Closure{args: [:derive_path]}]
               }
             }
           } = List.last(body)
  end

  test "dogfooded item decoders expose structural AST boundaries" do
    item_decoders = RustQ.NativeCodegen.Decoders.Item.__rustq_asts__()

    assert %AST.Function{name: :decode_ast_function, body: function_body} =
             Enum.find(item_decoders, &(&1.name == :decode_ast_function))

    assert %AST.ExprStmt{expr: %AST.Try{}} = hd(function_body)
    assert %AST.Let{pattern: %AST.PatVar{name: :args}} = Enum.at(function_body, 3)

    assert %AST.Return{
             expr: %AST.PathCall{path: %AST.Path{parts: [:super, :parse_item_function_args]}}
           } = List.last(function_body)

    assert %AST.Function{name: :decode_function_arg, body: arg_body} =
             Enum.find(item_decoders, &(&1.name == :decode_function_arg))

    assert %AST.ExprStmt{expr: %AST.Try{}} = hd(arg_body)

    assert %AST.Return{
             expr: %AST.PathCall{path: %AST.Path{parts: [:super, :parse_function_arg]}}
           } = List.last(arg_body)
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
      :decode_ast_static,
      :decode_ast_function,
      :decode_ast_struct,
      :decode_ast_macro_item,
      :decode_ast_macro_item_call,
      :decode_ast_enum,
      :decode_function_arg,
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
