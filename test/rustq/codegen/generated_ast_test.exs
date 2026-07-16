defmodule RustQ.Codegen.GeneratedASTTest do
  use ExUnit.Case, async: true

  alias RustQ.Codegen
  alias RustQ.Codegen.Decoders
  alias RustQ.Codegen.Decoders.Item, as: ItemDecoders
  alias RustQ.Codegen.Decoders.Type, as: TypeDecoders
  alias RustQ.Codegen.Dispatch
  alias RustQ.Codegen.Modules
  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Rust.AST.Schema

  alias RustQ.Rust.AST.{
    Closure,
    ExprStmt,
    Function,
    FunctionArg,
    If,
    Let,
    MacroItemCall,
    Match,
    MethodCall,
    Module,
    Ok,
    Path,
    PathCall,
    PatPath,
    Return,
    Try,
    TypeNifResult,
    TypePath,
    TypeRef,
    Var,
    VecLiteral
  }

  test "generates parseable AST support" do
    source = Codegen.generated_ast_support()

    assert {:ok, _template} = RustQ.parse(source, "generated_ast.rs")
  end

  test "generated modules are AST-backed" do
    modules = Modules.asts()

    assert %Module{name: :atoms, items: [%MacroItemCall{}], vis: :crate} =
             Enum.find(modules, &match?(%Module{name: :atoms}, &1))

    assert %Module{name: :ast_modules, items: constants, vis: :crate} =
             Enum.find(modules, &match?(%Module{name: :ast_modules}, &1))

    constant_names = constants |> Enum.map(& &1.name) |> MapSet.new()
    assert MapSet.member?(constant_names, :FUNCTION)
    refute MapSet.member?(constant_names, :ARM)
    refute MapSet.member?(constant_names, :ATTRIBUTE)
    refute MapSet.member?(constant_names, :DERIVE)
    refute MapSet.member?(constant_names, :FUNCTION_ARG)
    refute MapSet.member?(constant_names, :STRUCT_FIELD)
    refute MapSet.member?(constant_names, :ENUM_VARIANT)

    assert %Function{
             name: :atom,
             vis: :crate,
             args: [
               %FunctionArg{name: :env, type: %TypePath{parts: [:Env]}},
               %FunctionArg{
                 name: :name,
                 type: %TypeRef{inner: %TypePath{parts: [:str]}}
               }
             ],
             returns: %TypeNifResult{inner: %TypePath{parts: [:Atom]}}
           } = Enum.find(List.flatten(modules), &match?(%Function{name: :atom}, &1))
  end

  test "dispatch functions cover every externally decodable schema node" do
    dispatch = Dispatch.asts()
    names = dispatch |> Enum.map(& &1.name) |> MapSet.new()

    expected_dispatch = %{
      item: :decode_ast_item,
      type: :decode_ast_type,
      pat: :decode_ast_pat,
      stmt: :decode_ast_stmt,
      expr: :decode_ast_expr
    }

    assert MapSet.subset?(MapSet.new(Map.values(expected_dispatch)), names)

    for {category, function_name} <- expected_dispatch do
      assert %Function{body: [%Return{expr: %Match{arms: arms}}]} =
               Enum.find(dispatch, &(&1.name == function_name))

      actual_consts = dispatch_constants(arms)

      expected_consts =
        category
        |> Schema.nodes()
        |> Enum.map(& &1.rust_const)
        |> MapSet.new()

      assert actual_consts == expected_consts,
             "#{function_name} dispatch does not match #{category} schema nodes"
    end
  end

  test "type ref decoder delegates only the syn ref construction boundary" do
    assert %Function{body: body} =
             TypeDecoders
             |> MetaAST.functions()
             |> Enum.find(&(&1.name == :decode_type_ref))

    assert %Return{
             expr: %PathCall{path: %Path{parts: [:super, :parse_type_ref]}}
           } = List.last(body)
  end

  test "type container decoders use generic type construction" do
    decoders = MetaAST.functions(TypeDecoders)

    for name <- [
          :decode_type_option,
          :decode_type_result,
          :decode_type_nif_result,
          :decode_type_vec
        ] do
      assert %Function{body: body} = Enum.find(decoders, &(&1.name == name))

      assert %Return{
               expr: %PathCall{
                 path: %Path{parts: [:super, :parse_type_generic]},
                 args: [_path, %VecLiteral{}]
               }
             } = List.last(body)
    end
  end

  test "dogfooded type helpers cover path and lifetime list boundaries" do
    type_decoders = MetaAST.functions(TypeDecoders)

    assert %Function{name: :path_parts, body: path_body} =
             Enum.find(type_decoders, &(&1.name == :path_parts))

    assert %Let{
             expr: %Try{
               expr: %PathCall{path: %Path{parts: [:super, :decode_string_list]}}
             }
           } =
             hd(path_body)

    assert %Return{expr: %Ok{expr: %MethodCall{method: :join}}} = List.last(path_body)

    assert %Function{name: :decode_lifetime_list, body: lifetime_body} =
             Enum.find(type_decoders, &(&1.name == :decode_lifetime_list))

    assert [
             %Return{
               expr: %PathCall{path: %Path{parts: [:super, :decode_string_list]}}
             }
           ] =
             lifetime_body
  end

  test "dogfooded derive decoder uses iterator lowering" do
    item_decoders = MetaAST.functions(ItemDecoders)

    assert %Function{name: :decode_derive_path_list, body: body} =
             Enum.find(item_decoders, &(&1.name == :decode_derive_path_list))

    assert %Return{
             expr: %MethodCall{
               method: :collect,
               receiver: %MethodCall{
                 method: :map,
                 args: [%Closure{args: [:derive_path]}]
               }
             }
           } = List.last(body)
  end

  test "dogfooded item decoders expose structural AST boundaries" do
    item_decoders = MetaAST.functions(ItemDecoders)

    assert %Function{name: :decode_ast_function, body: function_body} =
             Enum.find(item_decoders, &(&1.name == :decode_ast_function))

    assert %ExprStmt{expr: %Try{}} = hd(function_body)

    assert %Return{
             expr: %PathCall{path: %Path{parts: [:super, :parse_item_function_args]}}
           } = List.last(function_body)

    assert %Function{name: :decode_function_arg, body: arg_body} =
             Enum.find(item_decoders, &(&1.name == :decode_function_arg))

    assert %ExprStmt{expr: %Try{}} = hd(arg_body)

    assert %Return{
             expr: %If{
               condition: %Var{name: :receiver},
               then: [
                 %Return{
                   expr: %PathCall{path: %Path{parts: [:super, :parse_function_receiver]}}
                 }
               ],
               else: else_body
             }
           } = List.last(arg_body)

    assert %Return{
             expr: %PathCall{path: %Path{parts: [:super, :parse_function_arg]}}
           } = List.last(else_body)
  end

  test "dogfooded decoder modules cover generated decoder categories" do
    decoder_names =
      Decoders.asts()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    expected_expr_decoders =
      Schema.nodes(:expr)
      |> Enum.map(&String.to_atom("decode_expr_#{&1.name}"))

    expected_stmt_decoders =
      Schema.nodes(:stmt)
      |> Enum.map(&String.to_atom("decode_stmt_#{&1.name}"))

    expected_pat_decoders =
      Schema.nodes(:pat)
      |> Enum.reject(&(&1.name == :pat_atom_guard))
      |> Enum.map(&String.to_atom("decode_#{&1.name}"))

    expected_type_decoders =
      Schema.nodes(:type)
      |> Enum.map(&String.to_atom("decode_#{&1.name}"))

    expected_item_decoders =
      Schema.nodes(:item)
      |> Enum.map(&String.to_atom("decode_ast_#{&1.name}"))
      |> Kernel.++([:decode_function_arg, :decode_struct_field, :decode_enum_variant])

    for decoder <-
          expected_item_decoders ++
            expected_type_decoders ++
            expected_expr_decoders ++ expected_stmt_decoders ++ expected_pat_decoders do
      assert MapSet.member?(decoder_names, decoder), "missing dogfooded decoder #{decoder}"
    end
  end

  defp dispatch_constants(arms) do
    arms
    |> Enum.flat_map(fn
      %{pattern: %PatPath{path: %Path{parts: [:ast_modules, rust_const]}}} -> [rust_const]
      _badarg_arm -> []
    end)
    |> MapSet.new()
  end
end
