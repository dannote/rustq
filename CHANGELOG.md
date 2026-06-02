# Changelog

## v0.2.0 - 2026-06-02

- Replace the separate `__expr_`, `__type_`, and `__splice_` placeholder
  prefixes with one visually distinct `__rq_` placeholder prefix.
- Templates now use forms like `__rq_Name`, `__rq_value!()`,
  `__rq_fields: (),`, and `__rq_items!();`.

## v0.1.2 - 2026-06-02

- Let Rustler schema field types reference schema nodes and tagged enums by
  schema name, so examples can use `Content` instead of generated Rust names
  like `ExContent`.

## v0.1.1 - 2026-06-02

- Keep the packaged NIF crate out of parent Cargo workspaces when RustQ is used
  inside workspace-based projects.

## v0.1.0 - 2026-06-02

Initial release.

- Parse, validate, render, bind, and splice Rust templates from Elixir.
- `~R` sigil for inline Rust templates.
- Rust fragment builders for functions, structs, enums, impls, fields, constants, uses, modules, and type aliases.
- Rustler helper generators for atoms, NIFs, resources, option decoders, term helpers, term decoders, NIF structs, tagged enums, cached atoms, safe term builders, and explicit raw `NIF_TERM` builders.
- `rustq.exs` manifest DSL plus `mix rustq.gen` for generated file syncing and stale checks.
- Rustler schema DSL for generating Rust NIF structs and tagged enums from Elixir schema definitions.
