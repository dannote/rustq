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
