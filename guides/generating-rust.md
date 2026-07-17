# Generating Rust

This guide covers the mechanics of checked files, templates, AST, splices, and
Rust metadata. Most new NIFs should start with `RustQ.Native`, which owns the
crate and does not require `rustq.exs`. Use the machinery here when generated
files are intentionally checked in, several generators contribute to one native
crate, or substantial handwritten Rust surrounds generated regions.

Keep Rust structural until the final rendering boundary: Rusty-Elixir for
behavior, ordinary Elixir macros for composition, RustQ AST for Rust-only
structure, and parseable Rust templates for handwritten Rust with generated
slots.

For authoring philosophy and inference, read [Using RustQ Well](using-rustq-well.md).
For generated Rustler codecs and wrappers, read
[Generating Rustler Boundaries](rustler-generation.md).

## Checked generation with `rustq.exs`

A `rustq.exs` file is an ordinary Elixir composition root:

```elixir
use RustQ.Config

alias RustQ.Rustler.Term

require_file "lib/my_app/codegen/content_schema.ex"

rust "native/my_nif/src/generated_term_helpers.rs" do
  Term.helpers(type_key: "atoms::r#type()")
end

rust "native/my_nif/src/generated_content.rs" do
  MyApp.Codegen.ContentSchema.rust_items()
end
```

Generate all targets or verify that checked-in output is fresh:

```bash
mix rustq.gen
mix rustq.gen --check
mix rustq.gen term_helpers
```

Path-only targets infer their name from the file name and strip a leading
`generated_`. Keep orchestration in `rustq.exs`; keep schemas and generation
logic in normal modules that can be tested directly.

## Real Rust templates

Templates are valid Rust with placeholders in parseable syntax positions:

```rust
pub struct __rq_Resource {
    __rq_fields: (),
}

impl __rq_Resource {
    __rq_methods!();
}
```

Bind identifiers and splice structural fields or items from Elixir:

```elixir
alias RustQ.Rust.AST.Builder, as: A
alias RustQ.Rust.AST.ItemBuilder, as: I
require A
require I

RustQ.render_file!("priv/templates/resource.rs",
  bind: [Resource: :User],
  splice: [
    fields: [
      I.field(:id, :i64, vis: :pub),
      I.field(:name, :String, vis: :pub)
    ],
    methods: [
      I.function :id, args: [A.receiver()], returns: :i64 do
        A.return(A.field(:self, :id))
      end
    ]
  ]
)
```

RustQ parses the template before replacement. A value cannot be injected into an
arbitrary token string accidentally; each placeholder has a Rust syntax
position and each splice has a fragment category.

Large templates may include Rust partials:

```rust
pub struct __rq_Resource {
    __rq_include!("resource/fields.rs");
}
```

File includes are resolved relative to the including template. String templates
can opt into the same behavior with `include_dir:`. Include failures carry a
structured include stack.

## Placeholder forms

The placeholder spelling follows the Rust syntax position while sharing the
visible `__rq_` prefix:

- `__rq_Name` — identifier, path, type, or lifetime binding
- `__rq_value!()` — expression or type binding
- `__rq_items!();` — item splice
- `__rq_methods!();` — impl-item splice
- `__rq_body!();` — statement splice
- `__rq_arms => unreachable!(),` — match-arm splice
- `__rq_fields: (),` — struct-field splice
- `fn target(__rq_args: ()) {}` — function-argument splice
- `__rq_include!("relative/path.rs");` — template partial

Placeholders are not expanded inside arbitrary macro token trees. Bind a value
outside a macro invocation when necessary:

```rust
let value = __rq_value!();
println!("{}", value);
```

## RustQ AST builders

Use AST builders when the generated structure is data-shaped or when there is no
honest Elixir-shaped surface for the Rust construct:

```elixir
alias RustQ.Rust.AST.Builder, as: A
alias RustQ.Rust.AST.ItemBuilder, as: I
alias RustQ.Rust.AST.TypeBuilder, as: T

items = [
  A.use([:std, :sync, :OnceLock]),
  A.const(:TABLE, T.ref(:str), A.lit("users"), vis: :pub),
  %RustQ.Rust.AST.Struct{
    name: :User,
    vis: :pub,
    derive: [:Clone, :Debug],
    fields: [I.field(:id, :i64, vis: :pub)]
  }
]
```

AST nodes can be passed directly to template splices and `rustq.exs` targets.
Use `RustQ.Rust.render/1` only when a caller explicitly needs source text. If a
repeated Rust construct is missing from the AST, add a node or builder rather
than growing string templates.

Compiled `defrust` functions are available structurally through
`RustQ.Meta.AST.functions/1` and `RustQ.Meta.AST.function!/2`. These are the
public bridge from Rusty-Elixir modules to larger generators.

## Compose splice sources

A template can accept several independently produced splice sources. Duplicate
splice names are concatenated in order:

```elixir
RustQ.render_file!("native/src/generated.template.rs",
  splice: [
    MyApp.BaseGenerator.splices(schema),
    MyApp.NativeGenerator.splices(schema),
    items: additional_items
  ]
)
```

Use `RustQ.Splice.merge/1` when the combined splice set is needed separately:

```elixir
splices =
  RustQ.Splice.merge([
    MyApp.BaseGenerator.splices(schema),
    MyApp.NativeGenerator.splices(schema),
    items: additional_items
  ])
```

## Read real Rust metadata

Do not duplicate external Rust declarations in Elixir tables. `RustQ.Syn` parses
real Rust through `syn`:

```elixir
file = RustQ.Syn.parse_file!("native/foo/src/lib.rs")
methods = RustQ.Syn.methods(file)

index = RustQ.Syn.Index.from_paths(Path.wildcard("native/foo/src/**/*.rs"))
method = RustQ.Syn.Index.method!(index, "Canvas", "draw_rect")
```

For Rusty-Elixir call inference, configure source metadata at the module:

```elixir
use RustQ.Meta,
  rust_sources: ["native/my_nif/src/helpers.rs"],
  rust_packages: [{"skia-safe", manifest_path: "native/my_nif/Cargo.toml"}]
```

RustQ preserves structured paths, references, arrays, bare function types,
generic arguments, and `impl Trait` bounds while retaining source forms for
unsupported token-level details.

## Formatting and validation

Pass `rustfmt: true` to format final output through `rustfmt --emit stdout`:

```elixir
RustQ.render_file!("native/src/generated.template.rs",
  splice: [items: items],
  rustfmt: true
)
```

A command path may be provided instead. Formatting and parse failures return
structured RustQ errors rather than silently emitting invalid source.

Validate focused fragments in the same categories used by splices:

```elixir
alias RustQ.Rust.AST.PatternBuilder, as: P
require RustQ.Rust.AST.Builder, as: A

RustQ.valid_fragment?(:field, "pub id: i64")
RustQ.parse_fragment!(:arm, A.arm(P.some(:value), do: :value))
```

Consumer tests can verify generated functions and compile rendered Rust:

```elixir
use RustQ.Test, async: true

assert rust_source!(MyApp.Native, :decode_impl) =~ "fn decode_impl"
assert rust_source!(MyApp.Native, :decode) =~ ~r/fn decode/
assert nif_exported?(MyApp.Native, :decode, 1)
assert RustQ.valid?(rust_source!(MyApp.Native), "my_app_native.rs")
```

Run `mix rustq.gen --check`, Cargo formatting/checks, and downstream tests in CI.
Generated Rust should be valid and lint-clean, but the Elixir generator should
also remain readable.
