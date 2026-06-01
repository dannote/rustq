# RustQ

RustQ is Rust template quasiquoting for Elixir.

It lets Elixir code generate Rust from real `.rs` templates: parse a template,
bind placeholder identifiers and expressions, splice generated declarations, and
emit formatted Rust source through a Rustler NIF powered by `syn` and
`prettyplease`.

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

## File templates

```elixir
"priv/templates/resource.rs"
|> RustQ.from_file!()
|> RustQ.bind(Resource: :User)
|> RustQ.splice(:fields, [Rust.field(:id, :i64, vis: :pub)])
|> RustQ.codegen!()
```

Or render in one call:

```elixir
RustQ.render_file!("priv/templates/resource.rs",
  bind: [Resource: :User],
  splice: [fields: [Rust.field(:id, :i64, vis: :pub)]]
)
```

## Rust builders

```elixir
:users
|> Rust.mod()
|> Rust.pub()
|> Rust.item(Rust.type_alias(:UserId, :i64, vis: :pub))
|> Rust.item(Rust.const(:TABLE, {:ref, :str}, Rust.expr(~s("users")), vis: :pub))
```

## Rustler helpers

```elixir
RustQ.Rustler.atoms([:ok, :error, {"r#type", "type"}])
RustQ.Rustler.nif(:add, args: [a: :i64, b: :i64], returns: :i64, body: "a + b")
RustQ.Rustler.init(MyApp.Native)
```

Common Rustler decoding helpers can be generated as Rust items:

```elixir
RustQ.Rustler.term_helpers(type_key: "atoms::r#type()")

RustQ.Rustler.term_decoder(:ProgramInput,
  fields: [
    body: [type: {:vec, "Term<'a>"}, key: "atoms::body()", required: true]
  ]
)

RustQ.Rustler.nif_struct(:ExText, "Folio.Content.Text",
  fields: [text: :String, size: {:option, :String}]
)

RustQ.Rustler.tagged_enum(:ExContent,
  tag: "atom_struct()",
  variants: [
    Text: [type: :ExText, module: "Elixir.Folio.Content.Text"],
    Space: [type: :ExSpace, module: "Elixir.Folio.Content.Space"]
  ]
)
```

`term_decoder/2` field options:

- `:type` — Rust field/decode type.
- `:key` — Rust expression used as the map key.
- `required: true` — decode with `?` instead of returning an option.
- `default: "..."` — fallback Rust expression for missing/invalid optional values.
- `decode: "..."` — custom Rust expression for the field value.
- `missing: "..."` / `invalid: "..."` — custom required-field errors for non-`NifResult` decoders.

Function options include `result: "R"` for custom result aliases,
`:lifetime`, `:fn`, `:term_arg`, and `:term_type`.

For larger Rustler type surfaces, define an Ecto-style schema module:

```elixir
defmodule MyApp.Codegen.ContentSchema do
  use RustQ.Rustler.Schema

  schema MyApp.Content, rust_prefix: "Ex", tag_field: :__struct__ do
    default_attrs ["allow(dead_code)"]
    type :content, :ExContent

    node Text do
      field :text, :String
      field :size, {:option, :String}
    end

    node Space do
    end

    node Paragraph do
      field :body, {:vec, :content}
    end

    tagged_enum Content do
      variants :all
      unknown :unknown_content_variant
    end
  end
end
```

Then use `MyApp.Codegen.ContentSchema.rust_items()` in `rustq.exs`.
Field optionality is explicit in the Rust type (`{:option, :String}`), rather
than `required: true` flags.

## Generated files

Projects can declare generated outputs in `rustq.exs` and use RustQ's shared
write/check task:

```elixir
import RustQ.Config

rust_items "native/my_nif/src/generated_term_helpers.rs",
  items: RustQ.Rustler.term_helpers(type_key: "atoms::r#type()")

generate :schema, "native/my_nif/src/generated_schema.rs" do
  render "__splice_items!();",
    splice: [items: [RustQ.Rust.struct(:User, fields: [RustQ.Rust.field(:id, :i64)])]]
end
```

Then run:

```sh
mix rustq.gen
mix rustq.gen --check
mix rustq.gen term_helpers
```

Path-only `rust_items` targets infer their name from the filename and strip a
leading `generated_`, so `generated_term_helpers.rs` can be selected with
`mix rustq.gen term_helpers`.

## Fragment validation

```elixir
RustQ.parse_fragment(:field, "pub id: i64")
RustQ.parse_fragment!(:arm, Rust.arm("Some(value)", "value"))
RustQ.valid_fragment?(:stmt, "let value = 1;")
```

## Placeholder forms

Rust templates stay parseable by using ordinary identifiers and macro calls:

- `__Name` — identifier/type-path replacement
- `__expr_name!()` — expression replacement
- `__type_name!()` — type replacement
- `__splice_name!();` — item, impl item, or statement splice point
- `__splice_name: (),` — named-field splice point inside structs

## Status

Early prototype. The current implementation mutates parseable Rust templates in
the Rust NIF, validates with `syn`, and formats with `prettyplease`. The API is
intentionally shaped after `oxc_ex`: `parse! |> bind |> splice |> codegen!`.
