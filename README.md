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
pub struct __rq_Resource {
    __rq_fields: (),
}

impl __rq_Resource {
    __rq_methods!();

    pub fn table() -> &'static str {
        __rq_table_name!()
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

Large templates can be split into Rust partials. Includes are expanded before
Rust parsing and are resolved relative to the including file:

```rust
// priv/templates/resource.rs
pub struct __rq_Resource {
    __rq_include!("resource/fields.rs");
}

impl __rq_Resource {
    __rq_include!("resource/methods.rs");
}
```

For string templates, pass `include_dir: "priv/templates"` to enable include
expansion. Include errors return structured metadata, including
`:include_stack`, so callers can present their own diagnostics.

## Placeholder forms

RustQ placeholders use the visually distinct `__rq_` prefix. The exact shape
matches the Rust syntax position, but the name is consistent with the Elixir
`bind:` or `splice:` key:

- `__rq_Name` — identifier, type path, or lifetime replacement.
- `__rq_value!()` — expression or type replacement.
- `__rq_items!();` — item splice point.
- `__rq_methods!();` — impl-item splice point.
- `__rq_body!();` — statement splice point.
- `__rq_arms => unreachable!(),` — match-arm splice point.
- `__rq_fields: (),` — struct-field splice point.
- `__rq_include!("relative/path.rs");` — file include expanded before parsing.
- `fn target(__rq_args: ()) {}` — function-argument splice point.

Placeholders are replaced in parsed Rust syntax positions, not inside arbitrary
macro token trees. If you need a generated value in a macro call, bind it outside
the macro first:

```rust
let value = __rq_value!();
println!("{}", value);
```

instead of:

```rust
println!("{}", __rq_value!());
```

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

For larger wrapper bodies, prefer real Rust templates with placeholders over
assembling statement lists in Elixir.

## `defrust` macro frontend

RustQ also has an experimental valid-Elixir frontend for Rusty-Elixir codegen.
`defrust` reads normal `@spec` types and lowers ordinary Elixir syntax into the
Rust AST used by the native renderer:

```elixir
defmodule MyApp.Native.Generated do
  use RustQ.Meta
  alias RustQ.Type, as: R

  @spec decode_optional(term()) :: R.nif_result(Expr.t())
  defrust decode_optional(term) do
    optional_expr = unwrap!(Super.decode_optional_expr_field(term, "expr"))

    case optional_expr do
      nil -> expr!(:ok)
      expr -> expr!({:ok, expr})
    end
  end
end
```

Use semantic helpers such as `expr!`, `pat!`, and `stmt!` for Rust-shaped values
that are still authored as valid Elixir. `Super.*` calls mark the boundary to
handwritten Rust primitives. Raw token escapes (`raw_expr!`, `raw_pat!`,
`raw_stmt!`, `raw_arm!`) are explicit low-level escape hatches for cases not yet
covered by semantic helpers.

RustQ dogfoods this layer in `RustQ.NativeCodegen.Decoders.*` to generate much of
its own native AST decoder support.

Current `defrust` subset:

- idiomatic Rust-facing attributes before `defrust`, including `@nif schedule: "DirtyCpu"` and `@allow :dead_code`
- Skia-driven Rust AST nodes such as `impl`, `if let`, `for`, turbofish calls, byte strings, casts, indexing/ranges, and richer operators
- ordinary assignment as Rust `let`, explicit `assign!`, explicit `return!`, final expressions, `if`, and `case`
- aliases, remote calls, method calls, local calls, expression/item macro calls, fields, refs, tuples, lists as `vec![...]`, and literals
- `Enum.map/2` with a single-argument anonymous function lowers to an iterator chain
- `Option`, `Result`, and `NifResult` return/branch wrapping from `@spec`
- selected `@type` forms: atom unions, `nil | t`, `{:ok, t} | {:error, e}`, maps, structs, and tagged tuple unions
- semantic helpers: `expr!`, `pat!`, `stmt!`, `arm!`
- explicit raw escapes: `raw_expr!`, `raw_pat!`, `raw_stmt!`, `raw_arm!`

`Super.*` calls are intentional primitive-boundary calls into nearby handwritten
Rust for Rustler term APIs, generic `syn` parsing/assembly, or collection glue.
Prefer extending `RustQ.Rust.AST` and `RustQ.Meta.Lower` before adding new
primitive helpers.

`RustQ.Meta.Type` is the typespec-driven path for `defrust`. `RustQ.Rustler.Schema`
remains the explicit public schema DSL for Rustler struct/tagged-enum generation;
the two may share internals later, but their authoring surfaces are currently
separate by design.

Native AST rendering is the primary backend. During development you can disable
silent fallback rendering with:

```elixir
config :rustq, :strict_native_ast, true
```

Use strict mode when adding AST nodes or native decoder coverage so unsupported
nodes fail visibly instead of falling back to the Elixir debug renderer.

## Optional rustfmt

Pass `rustfmt: true` to format generated source through `rustfmt --emit stdout`:

```elixir
RustQ.render_file!("native/src/generated.template.rs",
  splice: [items: items],
  rustfmt: true
)
```

You can also pass a command path/string with `rustfmt: "/path/to/rustfmt"`.
Rustfmt failures return structured `:rustfmt_error` metadata.

## Composing splices

When multiple generators contribute to one template, pass nested splice sources
or use `RustQ.Splice.merge/1`. Duplicate names are concatenated:

```elixir
RustQ.render_file!("native/src/generated.template.rs",
  splice: [
    MyApp.BaseGenerator.splices(schema),
    MyApp.NativeGenerator.splices(schema),
    items: RustQ.Rust.item("pub fn generated() {}")
  ]
)
```

For explicit composition:

```elixir
splices =
  RustQ.Splice.merge([
    MyApp.BaseGenerator.splices(schema),
    MyApp.NativeGenerator.splices(schema),
    items: RustQ.Rust.item("pub fn generated() {}")
  ])
```

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

RustQ.Rustler.nif_exports(
  render_png: [
    args: [env: "Env<'a>", batch: "Term<'a>"],
    returns: "NifResult<Term<'a>>",
    lifetime: :a,
    schedule: :dirty_cpu
  ]
)

RustQ.Rustler.term_helpers(type_key: "atoms::r#type()")
RustQ.Rustler.opts_helpers()
RustQ.Rustler.term_decoder(:ProgramInput,
  fields: [
    body: [type: {:vec, "Term<'a>"}, key: "atoms::body()", required: true]
  ]
)

RustQ.Rustler.resource_handle(:EncodedImage,
  fields: [bytes: "Vec<u8>"],
  handle_field: "ref"
)
```

Atom-based decoders and dispatchers are intentionally low-level so projects can
compose them into their own command, AST, or schema models:

```elixir
RustQ.Rustler.atom_decoder(:decode_blend_mode,
  returns: :BlendMode,
  cases: [src_over: "BlendMode::SrcOver", multiply: "BlendMode::Multiply"]
)

RustQ.Rustler.atom_dispatch(:draw_command,
  args: [surface: "&mut Surface", command: "Term<'a>"],
  on: "command.map_get(atoms::op())?.decode::<Atom>()?",
  cases: [rect: "draw_rect(surface, command)"],
  unknown: "Ok(())"
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

    node Enum, rust: :ExEnum, module: MyApp.Content.EnumList do
      field :children, {:vec, Content}
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
