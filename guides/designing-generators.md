# Designing RustQ Generators

A generator is product architecture, not a bag of build scripts. Its Elixir
source should explain the bridge more clearly than the generated Rust does.

This guide covers project organization. For template, AST, splice, and
`rustq.exs` mechanics, read [Generating Rust](generating-rust.md). For the
authoring hierarchy, read [Using RustQ Well](using-rustq-well.md).

## Use the smallest architecture that fits

Do not introduce a generator when one `RustQ.Native` module and a few `defnif`s
are enough. Add layers only when the project has independently changing schemas,
many generated targets, or an existing native crate with its own release policy.

A larger project can use these responsibilities:

- `MyApp.Codegen.*` — schemas, manifests, and orchestration
- `MyApp.Codegen.Rusty.*` — `defrust` implementation modules
- `MyApp.Codegen.Rust.*` — RustQ AST and template composition
- `MyApp.Native` — runtime loader and public native API
- `MyApp.Native.GeneratedStubs` — generated fallback exports for an existing
  crate

These are conventions, not required framework namespaces. Keep fewer layers
when fewer layers are clearer.

## Keep `rustq.exs` boring

Use `rustq.exs` as a composition root. Put schemas, policy, and build functions
in ordinary modules:

```elixir
use RustQ.Config

require_file("lib/my_app/codegen/atoms.ex")
require_file("lib/my_app/codegen/nifs.ex")
require_file("lib/my_app/codegen/targets.ex")

for {name, target} <- MyApp.Codegen.Targets.all() do
  generate name, target.path do
    build(target.build)
  end
end
```

Do not bury source scanning, implementation lookup, or large encoder tables in
the manifest. Those operations deserve named functions and focused tests.

## Choose one owner for each fact

A fact should be authored once and projected where needed:

- function signatures belong in `@spec` or real Rust source
- external methods and generic bounds belong in Rust source/Cargo metadata
- RustQ-owned structural types belong in `@type` or one schema
- export lists and scheduler choices belong in explicit boundary policy
- atom values belong in source references or the schema that introduces them

Do not repeat arities, lifetimes, argument types, returns, fields, or variants in
parallel registries. An explicit export-name list is useful policy; a second
signature table for those exports is duplication.

## Keep policy separate from inference

Infer structure that has a trustworthy owner. Keep actual decisions visible:

- which functions are exported
- scheduler selection
- intentional atom or field renames
- lossy conversion
- resource synchronization
- unsafe boundaries
- platform and release targets

A generator should reduce duplicated facts without hiding safety and deployment
choices.

## Generate by responsibility

Prefer predictable outputs such as:

- `generated_atoms.rs`
- `generated_types.rs`
- `generated_nifs.rs`
- `generated_term_encoders.rs`
- `generated_resources.rs`

A small root module that includes focused generated files and domain modules is
easier to inspect than one monolithic output. Do not split tiny output merely to
satisfy a naming scheme.

## Keep domain semantics with the domain

Generic packages should own generic codecs and generation machinery. Product
packages should own product schemas, semantic defaults, and behavior. Do not
move application-specific interpretation into a generic RustQ helper to reduce a
few local lines.

Likewise, keep clear native algorithms in Rust. RustQ is most valuable where it
removes repetitive wrappers, codecs, registration, dispatch, and schema-shaped
code.

## Prefer normal Elixir composition

Use maps, structs, lists, functions, modules, protocols already present in the
project, and ordinary macros before creating a consumer-specific DSL. A DSL is
justified when it expresses stable domain language—not merely because a large
keyword list looks unattractive.

Use helper functions returning AST or quoted Rusty-Elixir. Use
`unquote_splicing` for repeated source. Use `RustQ.Splice.merge/1` when several
independent generators contribute to one template. Do not create string-returning
helpers for complete Rust functions.

## Optimize for inspection

Both sides of generation should be reviewable:

- a reader should find the source of a generated field or wrapper quickly
- generated files should have deterministic ownership and order
- failures should report the target and structural phase
- checked generation should fail cleanly when output is stale
- tests should exercise behavior or compile output, not grep policy from source

Abstraction is not automatically clarity. Concrete public Elixir specs may
repeat intentionally because they document API. Remove repetition when it
creates competing sources of truth or exposes internal generator machinery to
consumers.

## Validate the real boundary

A generator change is not complete when an Elixir unit test passes. Run:

1. focused schema and AST tests
2. `mix rustq.gen --check`
3. Rust formatting, checking, and Clippy
4. runtime or boundary tests
5. downstream CI when shared metadata or generation changes

For packages, validate the built Hex artifact in an external consumer so hidden
source-checkout dependencies and missing packaged files are caught before
release.
