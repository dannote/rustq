# Changelog

## Unreleased

## v0.9.7 - 2026-07-10

- Add structural schema field and shorthand-field splices for projection-driven
  Rust struct declarations and literals.

## v0.9.6 - 2026-07-10

- Generate one Elixir NIF stub module from mixed Rust source metadata and RustQ
  AST functions, including automatic Rustler `Env` exclusion.

## v0.9.5 - 2026-07-10

- Preserve no-parentheses function-pointer field access in expected-type
  positions instead of lowering fields named `decode` as generic Rustler method
  calls.

## v0.9.4 - 2026-07-10

- Add AST-backed Rustler term encoders with nested, conditional, optional,
  collection, adapter, helper, and fallback field projections.
- Add source-derived Rustler NIF wrappers and Elixir fallback stubs so one
  manifest and the handwritten Rust implementation signatures determine both
  sides of the boundary.
- Discover atom references inside Rust macro token trees and document stable,
  structural Rustler generation workflows.
- Add optional Rustler map decoders and improve option/method result inference.

## v0.9.3 - 2026-07-06

- Infer `Option<T>` author input for expected `Option<&T>` adapter arguments,
  including fallible `NifResult<Option<T>>` values passed to
  `impl Into<Option<&T>>` Rust methods.
- Preserve owned option locals while emitting `.as_ref()` at the eventual call
  site to avoid borrowing from temporaries.

## v0.9.2 - 2026-07-06

- Improve Rusty-Elixir propagation and borrow inference for fallible option
  cases, `some(...)`, `unwrap_or`, `decode_as!`, `map_get`, fallible reference
  access, list/slice arguments, loop bindings, and method arguments.
- Improve callable metadata lookup for qualified method receivers and add corpus
  coverage for `impl Into<Option<T>>` argument propagation.
- Refresh README, guide, skill, and module docs around inference-first authoring
  with less explicit `unwrap!`, `ref`, and `mut_ref` boilerplate.

## v0.9.1 - 2026-07-06

- Improve expected-input inference for callable arguments, including fallible
  `case` scrutinees, associated calls, and slice/`Vec` borrow adaptation.
- Add corpus coverage for semantic `defrustmacro` item calls and recent
  propagation/borrow inference regressions.

## v0.9.0 - 2026-07-06

This release is a large Rusty-Elixir self-hosting and downstream dogfooding
release. It expands structural Rust generation, improves type-driven lowering,
and fixes a major compile-time performance regression exposed by Skia dogfood.

### Added

- Add Rust type item generation from `@type` aliases, including type aliases,
  structs, enums, and Rust-only support records that do not force generated
  Rustler term decoders.
- Add `R.enum(...)` for explicit Rust enum type items and fix zero-arity type
  alias resolution for bare `@type name :: ...` declarations.
- Add structural `macro_rules!` AST support and native validation/rendering for
  macro variables, captures, repetitions, and macro repeat expressions.
- Add AST walking utilities for RustQ AST traversal and mutation analysis.
- Add golden corpus tooling for Rusty-Elixir lowering, with coverage reporting
  by category.
- Add semantic `enum_variant(Type, :variant, ...)` lowering for constructing
  Rust enum variants from Rusty-Elixir without token macros.
- Add semantic item-producing `defrustmacro` calls and macro item call support.
- Add `defrustmacro` support for compact `skip_fields` and sparse struct field
  descriptor row patterns.
- Add idiomatic Clippy lint paths for Rust-facing attributes, such as
  `@allow Clippy.redundant_field_names` rendering to
  `#[allow(clippy::redundant_field_names)]`.
- Add dev-only RustQ Reach smell checks and dogfood them in strict mode for raw
  Rust escapes, low-level Rusty-Elixir control flow, trivial `defrust` wrappers,
  and blockless `defrustmod` aliases.

### Changed

- Extend `defrustmacro` with identifier/literal captures, item-generating inner
  `defrust` bodies, multiple generated item bodies, and `repeat ... do`
  macro-template repetitions.
- Lower calls to known `defrustmacro` helpers as generated Rust macro
  invocations, and support remote Rust macro calls such as `Debug.trace!(value)`.
- Replace ad hoc macro metavariable spacing cleanup with structural macro repeat
  expression rendering.
- Remove the process dictionary from Rusty-Elixir lowering; lowering state is now
  threaded explicitly through expression, call-argument, alias, array,
  control-flow, return, and expected-expression lowering.
- Make context-aware expression lowering the primary lowering path.
- Expand type-driven checking for expected expression positions, including
  returns, call arguments, struct fields, `case` arms, `if` branches,
  `with`/`for reduce` bodies, closures, field access, statics, array literals,
  and option `some(...)` wrappers.
- Infer downstream types through value uses such as comparisons,
  `binary_search_by_key`, receiver method calls, mutable `Vec::push`, option
  case bindings, option adapters, package free functions, and `Self`-based impl
  callables.
- Import free functions from configured Cargo packages in addition to impl
  methods.
- Resolve `Self` types in impl callable metadata to the concrete impl target.
- Keep `__rustq_callables__/0` exports limited to local RustQ callables instead
  of embedding all external/package callables into every module. External
  callables are still available during compilation through cached source/package
  resolution.
- Document item-generating `defrustmacro` patterns for compact generated Rust
  that keeps implementation logic in Rusty-Elixir.
- Document when to use ordinary Elixir `defmacro` for authoring-layer reuse
  versus `defrustmacro` for intentionally reducing generated Rust size.

### Fixed

- Parse Rust bare function pointer types structurally through `syn` metadata
  instead of regexing rendered Rust type strings.
- Mark function pointer types as non-decodable where Rustler decoding cannot be
  derived safely.
- Auto-borrow binary-search keys, array literals expected as slices, call
  arguments, option `some(...)` inners, option adapter inners, external statics,
  and several downstream value-use patterns.
- Avoid applying `?` to `Option<T>` values in `Result`/`NifResult` contexts where
  Rust does not support that propagation boundary.
- Infer external static types and generated static types for auto-borrowing.
- Preserve explicit `R.raw(...)` as an escape hatch while using structured `syn`
  metadata where available.
- Fix zero-cost package metadata reuse after Skia dogfood: generated checks that
  previously ballooned to roughly 75–80 seconds now avoid duplicating thousands
  of external callables into every module.

## v0.8.3 - 2026-06-28

- Infer propagation for source-backed receiver method calls when the receiver type is known.
- Index Rust source callables by normalized receiver target names.
- Strengthen metadata guidance for avoiding `unwrap!` when Rust source metadata can be configured.

## v0.8.2 - 2026-06-26

- Add the RustQ agent skill to the Hex package and documentation.
- Add guidance for authoring RustQ generators with `defrust`, AST builders,
  metadata, inference, and explicit escape boundaries.
- Document expression-oriented Rusty-Elixir style and recursion/reducer patterns.

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
