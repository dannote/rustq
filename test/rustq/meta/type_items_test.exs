Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.TypeItemsTest do
  use ExUnit.Case, async: true

  alias RustQ.Meta.GeneratedCase, as: Generated

  test "set-theoretic type aliases are available to specs" do
    assert %RustQ.Meta.Type{kind: :enum, rust: "Mode", meta: %{variants: [:src_over, :multiply]}} =
             Generated.__rustq_types__()[{:mode, 0}]

    assert %RustQ.Meta.Type{kind: :struct, rust: "Click", meta: %{fields: click_fields}} =
             Generated.__rustq_types__()[{:click, 0}]

    assert Enum.any?(
             click_fields,
             &match?({:name, %RustQ.Meta.Type{rust: "String"}, :required}, &1)
           )

    assert %RustQ.Meta.Type{kind: :tuple_enum, rust: "Event", meta: %{variants: event_variants}} =
             Generated.__rustq_types__()[{:event, 0}]

    assert {:Click, [%RustQ.Meta.Type{rust: "Click"}]} = List.keyfind(event_variants, :Click, 0)

    assert {:Resize, [%RustQ.Meta.Type{rust: "Resize"}]} =
             List.keyfind(event_variants, :Resize, 0)

    assert {:Scroll, [%RustQ.Meta.Type{rust: "Scroll"}]} =
             List.keyfind(event_variants, :Scroll, 0)

    assert %RustQ.Meta.Type{
             kind: :struct,
             rust: "RectOpts<'a>",
             ast: %RustQ.Rust.AST.TypePath{parts: ["RectOpts"], lifetimes: [:a]},
             meta: %{fields: fields}
           } = Generated.__rustq_types__()[{:rect_opts, 0}]

    assert Enum.any?(fields, &match?({:x, %RustQ.Meta.Type{rust: "f32"}, :required}, &1))
    assert Enum.any?(fields, &match?({:fill, %RustQ.Meta.Type{rust: "Term<'a>"}, :optional}, &1))

    assert %RustQ.Meta.Type{
             kind: :struct,
             rust: "NestedOpts<'a>",
             ast: %RustQ.Rust.AST.TypePath{parts: ["NestedOpts"], lifetimes: [:a]},
             meta: %{fields: nested_fields}
           } = Generated.__rustq_types__()[{:nested_opts, 0}]

    assert Enum.any?(
             nested_fields,
             &match?(
               {:rect,
                %RustQ.Meta.Type{
                  ast: %RustQ.Rust.AST.TypePath{parts: ["RectOpts"], lifetimes: [:a]}
                }, :required},
               &1
             )
           )

    assert Enum.any?(
             nested_fields,
             &match?({:label, %RustQ.Meta.Type{rust: "String"}, :optional}, &1)
           )
  end

  test "external t types keep structured generic arguments" do
    assert %RustQ.Meta.Type{
             rust: "MyMap<String, u32>",
             ast: %RustQ.Rust.AST.TypePath{
               parts: [:MyMap],
               generics: [
                 %RustQ.Rust.AST.TypePath{parts: [:String]},
                 %RustQ.Rust.AST.TypePath{parts: [:u32]}
               ]
             }
           } = RustQ.Meta.Type.from_spec_ast(quote(do: MyMap.t(String.t(), R.u32())))
  end

  test "type aliases generate structural Rust ASTs and decoders" do
    type_asts = Generated.__rustq_type_asts__()

    assert %RustQ.Rust.AST.Enum{
             name: :Mode,
             derive: [:Clone, :Copy, :Debug, :Eq, :PartialEq],
             variants: [
               %RustQ.Rust.AST.EnumVariant{name: :SrcOver},
               %RustQ.Rust.AST.EnumVariant{name: :Multiply}
             ]
           } = Enum.find(type_asts, &match?(%RustQ.Rust.AST.Enum{name: :Mode}, &1))

    assert %RustQ.Rust.AST.Function{
             name: :decode_mode_atom,
             args: [%RustQ.Rust.AST.FunctionArg{name: :value, type: "Atom"}],
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.Match{
                   arms: [
                     _,
                     _,
                     %RustQ.Rust.AST.Arm{
                       pattern: %RustQ.Rust.AST.PatWildcard{},
                       body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Err{}}]
                     }
                   ]
                 }
               }
             ]
           } =
             Enum.find(type_asts, &match?(%RustQ.Rust.AST.Function{name: :decode_mode_atom}, &1))

    assert %RustQ.Rust.AST.Struct{
             name: :NestedOpts,
             lifetime: :a,
             fields: [
               %RustQ.Rust.AST.StructField{
                 name: :rect,
                 type: %RustQ.Rust.AST.TypePath{parts: ["RectOpts"], lifetimes: [:a]}
               },
               %RustQ.Rust.AST.StructField{
                 name: :label,
                 type: %RustQ.Rust.AST.TypeOption{
                   inner: %RustQ.Rust.AST.TypePath{parts: [:String]}
                 }
               }
             ]
           } = Enum.find(type_asts, &match?(%RustQ.Rust.AST.Struct{name: :NestedOpts}, &1))

    assert %RustQ.Rust.AST.Enum{
             name: :Event,
             variants: [
               %RustQ.Rust.AST.EnumVariant{
                 name: :Click,
                 tuple: [%RustQ.Rust.AST.TypePath{parts: ["Click"]}]
               },
               %RustQ.Rust.AST.EnumVariant{
                 name: :Resize,
                 tuple: [%RustQ.Rust.AST.TypePath{parts: ["Resize"]}]
               },
               %RustQ.Rust.AST.EnumVariant{
                 name: :Scroll,
                 tuple: [%RustQ.Rust.AST.TypePath{parts: ["Scroll"]}]
               }
             ]
           } = Enum.find(type_asts, &match?(%RustQ.Rust.AST.Enum{name: :Event}, &1))
  end
end
