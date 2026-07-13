# Designing RustQ Generators

A RustQ consumer should make the authored bridge easier to understand than the
Rust it replaces. The generator is part of the product architecture, not a bag
of build scripts.

## Keep `rustq.exs` boring

Use `rustq.exs` as a composition root. Put domain metadata and build functions in
ordinary Elixir modules, then iterate over one target manifest.

```elixir
use RustQ.Config

require_file("lib/my_app/codegen/atoms.ex")
require_file("lib/my_app/codegen/nifs.ex")
require_file("lib/my_app/codegen/targets.ex")

MyApp.Codegen.Targets.all()
|> Enum.map(fn {name, target} ->
  generate name, Keyword.fetch!(target, :path) do
    build(Keyword.fetch!(target, :build))
  end
end)
|> List.last()
```

Prefer this over large inline encoder tables, source parsing pipelines, and
manual implementation lookup in `rustq.exs`.

## Use consistent layers

A useful naming convention is:

- `MyApp.Codegen.*` for schemas, manifests, and orchestration
- `MyApp.Codegen.Rusty.*` for `defrust` implementation modules
- `MyApp.Codegen.Rust.*` for Rust AST composition and rendering
- `MyApp.Native` for the runtime Rustler loader
- `MyApp.Native.GeneratedStubs` for generated fallback functions

Use `_impl` for handwritten Rust implementation functions behind generated NIF
wrappers. Avoid `_nif` on exported names when the surrounding `Native` module
already supplies that context.

Generated Rust files should use predictable responsibility-based names such as
`generated_atoms.rs`, `generated_nifs.rs`, `generated_term_encoders.rs`, and
`generated_types.rs`.

## Prefer ordinary manifests

Use lists, maps, structs, functions, and normal Elixir modules before creating a
consumer-specific DSL. A manifest should own policy that cannot be inferred:
which functions are exported, scheduling, semantic atom renames, and intentional
field projections.

Do not repeat signatures, arities, lifetimes, or field types when RustQ can read
them from Rust source, Rusty-Elixir specs, schemas, or generated AST metadata.

## Keep metadata near its owner

Long lists of generated function names should live beside the functions they
select. Shared defaults should have one owner. Generated atom keys should come
from source references or normalized encoder/schema metadata, with only true
identifier-to-value renames declared manually.

An explicit export-name list is useful policy. A second argument/return registry
for those exports is duplication.

## Optimize for inspection

Generated output should be split by responsibility when practical. A small root
Rust module that includes generated atoms, types, wrappers, and domain helpers is
easier to inspect than one monolithic generated file.

Do not abstract merely to reduce line count. Repetition can be valuable when it
keeps public Elixir typespecs concrete and readable. Remove repetition when it
creates two sources of truth or forces consumers to understand RustQ's internal
manifest representation.
