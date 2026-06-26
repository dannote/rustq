# Changelog

## Unreleased

## v0.8.1 - 2026-06-25

- Add Rustler fixed struct term helpers for cached keys, default values, and raw `NIF_TERM` map construction.
- Use `Atom::from_str` for generated cached atom helpers.
- Add missing Rust integer marker types to `RustQ.Type`.

## v0.8.0 - 2026-06-25

- Add semantic control-flow lowering for expression-oriented Rusty-Elixir.
- Support macro-generated `case` clauses in `defrust` lowering.

## v0.7.0 - 2026-06-25

- Add `ok_or!(option_expr, error_expr)` as the Rusty-Elixir idiom for explicit
  `Option<T>` to `Result<T, E>` propagation boundaries.
- Extend type-driven propagation inference with nested Rust module function
  metadata, downstream receiver-method let inference, `as_slice()` adapters,
  source-backed `From<A> for B` compatibility for `impl Into<B>`, and
  associated-type metadata such as `impl IntoIterator<Item = T>`.
- Add source-backed callable metadata from Rust source files, Cargo packages,
  and callable modules.
- Dogfood native RustQ AST generation in Rustler atom dispatch, tagged enum,
  macro item, and native codegen helper paths.
- Add structured diagnostics for RustQ configuration, source loading, lowering,
  and native rendering failures.

## v0.6.0 - 2026-06-19

- Reframe Rusty Elixir as the high-level `defrust` authoring surface.
- Add external Rust type specs through ordinary remote types such as
  `GeneratedOpts.OvalOpts.t(RustQ.Type.lifetime(:a))`.
- Add ordinary Elixir macro expansion before `defrust` lowering so reusable
  Rusty-Elixir body fragments can use `defmacro`, `quote`, and `unquote`.
- Lower plural alias calls such as `Atoms.fill()` to snake-case Rust module calls
  such as `atoms::fill()`.
- Demote `RustQ.Meta.quoted` and `RustQ.Type.path` to low-level escape
  hatches instead of the normal authoring style.
- Add small AST reuse bridges for RustQ-owned codegen helpers:
  `RustQ.Rust.ast_item/1`, `RustQ.Rust.ast_items/1`, and the internal
  `RustQ.Meta.item(module, name)` / `items(module, names)` / `ast!(module, name)`
  helpers.
- Add Rust AST support for receiver arguments and lifetime-bearing impl blocks,
  including Rustler shapes such as `impl<'a> rustler::Decoder<'a> for Type` and
  `fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a>`.
- Dogfood Rustler helper generation through `defrust` and RustQ AST builders:
  term helpers, opts helpers, term builders, cached atoms, atom decoders, tagged
  enum decoders/encoders, resources, and term decoder shells no longer rely on
  hand-written helper templates. Explicit raw `NIF_TERM` builders remain the
  unsafe escape hatch.

## v0.5.1 - 2026-06-15

- Add generic Rust expression builders:
  - `Rust.call_expr/3`
  - `Rust.some/1`
  - `Rust.none/0`
  - `Rust.tuple/1`
  - `Rust.cast/2`
  - `Rust.question/1`
  - `Rust.ref_expr/2`

## v0.5.0 - 2026-06-15

- Add template includes.
- Add composable RustQ splice groups.
- Use plain keyword splices for composition.
- Add structured include diagnostics.
- Add rustfmt option.
- Add generic Rust body/control-flow builders:
  - `Rust.block/1`
  - `Rust.let_/2`
  - `Rust.let_mut/2`
  - `Rust.assign/2`
  - `Rust.call_stmt/3`
  - `Rust.return_if/2`
  - `Rust.if_/3`
  - `Rust.if_let/4`
  - `Rust.match_/2`
- Document macro token placeholder limitation.

## v0.4.0 - 2026-06-06

- Add generic Rustler builders for atom decoders, atom dispatch functions, and
  keyword/options helper functions.

## v0.3.0 - 2026-06-06

- Remove the generic Rustler schema field group DSL. Prefer explicit fields in
  RustQ schemas or project-specific macros for domain shorthand.

## v0.2.2 - 2026-06-03

- Add `RustQ.Rustler.resource_handle/2` for generating a Rustler resource plus
  a decoder for Elixir-facing resource handle structs/maps.
- Add Rustler schema field groups for reusable field sets with `use_fields/1`.
- Let Rustler schema nodes override generated Rust type names and Elixir module
  names with `rust:` and `module:`.

## v0.2.1 - 2026-06-03

- Add `RustQ.Rustler.nif_export/2` and `nif_exports/1` for generating exported
  Rustler NIF functions that delegate to handwritten implementation functions.

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
