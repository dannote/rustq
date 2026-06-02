# RustQ

RustQ is Rust template quasiquoting for Elixir. It helps Elixir projects generate
Rust from real `.rs` templates instead of building Rust strings by hand.

Use it for Rustler projects, schema-driven NIF surfaces, or any codegen where you
want Rust syntax highlighting, Rust parsing, formatting, and AST-aware
placeholder replacement.

## Installation

Add RustQ to `mix.exs`:

```elixir
{:rustq, "~> 0.1", only: [:dev, :test], runtime: false}
```

RustQ compiles a Rustler NIF at generation time, so Rust/Cargo must be available
where `mix rustq.gen` or your own codegen task runs.

## Generate from real Rust templates

Templates are ordinary Rust with parseable placeholder forms:

```elixir
use RustQ.Sigil
alias RustQ.Rust

template = ~R"""
pub struct __Resource {
    __splice_fields: (),
}

impl __Resource {
    __splice_methods!();

    pub fn table() -> &'static str {
        __expr_table_name!()
    }
}
"""

code =
  template
  |> RustQ.parse!("resource.rs")
  |> RustQ.bind(Resource: :User, table_name: {:literal, "users"})
  |> RustQ.splice(:fields, [
    Rust.field(:id, :i64, vis: :pub),
    Rust.field(:name, :String, vis: :pub)
  ])
  |> RustQ.splice(:methods, [
    Rust.fn(:new,
      vis: :pub,
      args: [id: :i64, name: :String],
      returns: :Self,
      body: "Self { id, name }"
    )
  ])
  |> RustQ.codegen!()
```

For file templates:

```elixir
RustQ.render_file!("priv/templates/resource.rs",
  bind: [Resource: :User],
  splice: [fields: [RustQ.Rust.field(:id, :i64, vis: :pub)]]
)
```

## Placeholder forms

RustQ templates stay parseable Rust by using sentinel identifiers and macros:

- `__Name` — identifier or type-path replacement.
- `__expr_name!()` — expression replacement.
- `__type_name!()` — type replacement.
- `__splice_items!();` — item splice point.
- `__splice_methods!();` — impl-item splice point.
- `__splice_body!();` — statement splice point.
- `__splice_arms => unreachable!(),` — match-arm splice point.
- `__splice_fields: (),` — struct-field splice point.
- `fn target(__splice_args: ()) {}` — function-argument splice point.

## Rust builders

`RustQ.Rust` provides small Elixir builders for common Rust fragments:

```elixir
alias RustQ.Rust

items = [
  Rust.use([:std, :sync, :OnceLock]),
  Rust.const(:TABLE, {:ref, :str}, Rust.expr(Rust.literal("users")), vis: :pub),
  Rust.struct(:User,
    vis: :pub,
    derive: [:Clone, :Debug],
    fields: [Rust.field(:id, :i64, vis: :pub)]
  )
]
```

Use `Rust.raw/1`, `Rust.item/1`, `Rust.impl_item/1`, `Rust.stmt/1`,
`Rust.expr/1`, and `Rust.arm/1` when hand-written Rust is clearer than a builder.

## Rustler helpers

`RustQ.Rustler` generates common Rustler code as Rust fragments:

```elixir
RustQ.Rustler.atoms([:ok, :error, {"r#type", "type"}])
RustQ.Rustler.cached_atoms([:ok, node_changes: "nodeChanges"])

RustQ.Rustler.nif(:add,
  args: [a: :i64, b: :i64],
  returns: :i64,
  body: "a + b"
)

RustQ.Rustler.term_helpers(type_key: "atoms::r#type()")
RustQ.Rustler.term_decoder(:ProgramInput,
  fields: [
    body: [type: {:vec, "Term<'a>"}, key: "atoms::body()", required: true]
  ]
)
```

Safe term builders use `Term<'a>`:

```elixir
RustQ.Rustler.term_builders(include: [:map_from_terms, :struct_from_terms])
```

Low-level raw `NIF_TERM` helpers are explicit:

```elixir
RustQ.Rustler.nif_term_builders(include: [:map_from_nif_terms, :struct_from_nif_terms])
```

## Rustler schema DSL

For larger Elixir struct surfaces, define a schema once and generate Rust NIF
structs plus tagged enums:

```elixir
defmodule MyApp.Codegen.ContentSchema do
  use RustQ.Rustler.Schema

  schema MyApp.Content do
    default_attrs ["allow(dead_code)"]

    node Text do
      field :text, :String
      field :size, {:option, :String}
    end

    node Paragraph do
      field :body, {:vec, Content}
    end

    tagged_enum Content do
      variants :all
      unknown :unknown_content_variant
    end
  end
end
```

Optionality is part of the Rust type (`{:option, :String}`), not a separate
boolean flag.

## Generated files with `rustq.exs`

Create `rustq.exs` in your project root:

```elixir
use RustQ.Config

alias RustQ.Rustler

require_file "lib/my_app/codegen/content_schema.ex"

rust "native/my_nif/src/generated_term_helpers.rs" do
  Rustler.term_helpers(type_key: "atoms::r#type()")
end

rust "native/my_nif/src/generated_content.rs" do
  MyApp.Codegen.ContentSchema.rust_items()
end
```

The manifest is ordinary Elixir, so use aliases, helper functions, modules, and
macros to keep project-specific codegen readable.

Then run:

```sh
mix rustq.gen
mix rustq.gen --check
mix rustq.gen term_helpers
```

Path-only targets infer their name from the file name and strip a leading
`generated_`, so `generated_term_helpers.rs` is selectable as `term_helpers`.

Use `mix rustq.gen --check` in CI to fail when generated files are stale.

## Fragment validation

You can validate individual Rust fragments in the same contexts RustQ splices:

```elixir
RustQ.valid_fragment?(:field, "pub id: i64")
RustQ.parse_fragment!(:arm, RustQ.Rust.arm("Some(value)", "value"))
```

## License

MIT
