use RustQ.Config

generate :generated_ast_support, "native/rustq_nif/src/generated_ast.rs" do
  content RustQ.NativeCodegen.generated_ast_support()
end
