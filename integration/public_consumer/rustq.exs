use RustQ.Config

alias RustQ.Rust.AST.Builder, as: A
alias RustQ.Rustler.{Atom, Term}

require_file("lib/rustq_public_consumer/generated.ex")

rust "native/src/generated.rs" do
  [
    A.const(:ANSWER, :u32, 42, vis: :pub),
    Atom.declaration([:ok, :value]),
    RustQPublicConsumer.Generated.__rustq_items__(),
    Term.decoder(:Input,
      fields: [
        value: [type: "Term<'a>", key: A.path_call([:atoms, :value]), required: true]
      ]
    )
  ]
end
