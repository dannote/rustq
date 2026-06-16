# `defrust` / Rusty-Elixir plan

`defrust` is RustQ's valid-Elixir macro frontend for generating Rust. It uses
ordinary Elixir syntax, `@spec`/`@type` declarations, and a growing
`RustQ.Rust.AST` IR to produce Rust/Rustler code. The long-term goal is for
RustQ to dogfood this layer heavily enough that most RustQ-native codegen is
specified in Elixir and only true primitive boundaries remain handwritten Rust.

This document supersedes the original MVP checklist. The project was re-read as
of the current branch and the plan below reflects the current codebase:

- public Rust template API in `RustQ`, `RustQ.Template`, `RustQ.Config`, and
  `mix rustq.gen`
- legacy string/template builders in `RustQ.Rust` and `RustQ.Rustler.*`
- AST-first frontend in `RustQ.Meta`, `RustQ.Meta.Type`, `RustQ.Meta.Lower`, and
  `RustQ.Rust.AST.*`
- self-hosted native AST decoder generation in `RustQ.NativeCodegen.*`
- native primitive modules under `native/rustq_nif/src`
- behavioral and primitive-boundary tests under `test/rustq/ast`,
  `test/rustq/meta`, and `test/rustq/native_codegen`

## Non-negotiable design principles

1. **Valid Elixir only**
   - No fake Rust syntax in Elixir: no Rust `let`, Rust `?`, `Some(x)`, or
     Rust-style `->` except normal Elixir constructs.
   - Ordinary Elixir assignment lowers to Rust `let`.
   - Ordinary `case` lowers to Rust `match`.
   - Ordinary aliases/remote calls lower to Rust paths/calls when appropriate.

2. **Specs and types are source of truth**
   - `@spec` drives function signatures and return-context lowering.
   - `@type` drives generated Rust enums/structs/decoders where possible.
   - Prefer built-in Elixir types (`atom()`, `term()`, `boolean()`, etc.) when
     they fit; use `RustQ.Type` only for Rust-specific precision.

3. **Rust AST before strings**
   - Prefer `RustQ.Rust.AST` nodes and native rendering over handwritten Rust
     strings.
   - Add missing AST nodes or semantic lowerings before adding string helpers.
   - `AST.MacroItem` and explicit raw escapes are allowed, but should stay local
     and documented as escape hatches.

4. **Semantic forms are compiler input, not registries**
   - `expr!(...)`, `pat!(...)`, `stmt!(...)`, and `arm!(...)` are interpreted by
     `RustQ.Meta.Lower`.
   - Do not add parallel constructor registries or one native helper per semantic
     shape.
   - Token-only semantic escapes funnel through generic
     `parse_syn::<T>(quote!(...))`.

5. **Primitive boundaries stay narrow**
   - Handwritten Rust is acceptable for Rustler term APIs, `syn` parsing,
     `prettyplease` rendering, template AST mutation, collection iteration that
     Rusty-Elixir cannot yet express, and small `syn` assembly boundaries.
   - New native primitives should be generic, not shape-specific, unless there is
     a strong reason.

6. **Behavioral tests over source trivia**
   - Prefer native render behavior and schema coverage to brittle generated-source
     substring checks.
   - Every new `RustQ.Rust.AST.Schema` node must have native behavioral rendering
     coverage.

## Current architecture

### Public template/codegen surface

`RustQ` remains the stable public entrypoint:

- parses real Rust templates through the native `parse/1` NIF
- renders bindings/splices through the native template engine
- validates fragments by embedding them in parseable Rust contexts
- expands `__rq_include!(...)` on the Elixir side before native parsing
- optionally runs `rustfmt`

`RustQ.Config` and `mix rustq.gen` provide project-level generated file support.
The current repository manifest only generates `native/rustq_nif/src/generated_ast.rs`.

### Legacy Rust/Rustler builders

`RustQ.Rust` and `RustQ.Rustler.*` still intentionally exist. They are useful for
public API compatibility and for template-oriented generation. They are, however,
mostly string/template-backed. Future work should migrate reusable shapes into
`RustQ.Rust.AST` only when that improves dogfooding or public ergonomics; do not
rewrite all legacy builders just for churn.

### AST-first `defrust` path

`RustQ.Meta` collects `defrust` definitions, reads module `@spec` and `@type`,
lowers function bodies through `RustQ.Meta.Lower`, and exposes:

- `__rustq_asts__/0`
- `__rustq_types__/0`
- `__rustq_type_items__/0`
- `__rustq_items__/0`
- `__rustq_source__/0`

`RustQ.Meta.Type` currently supports:

- Rust primitive/container vocabulary through `RustQ.Type`
- built-in Elixir type mapping
- atom unions as Rust enums
- `nil | t` as `Option<T>`
- `{:ok, ok} | {:error, error}` as `Result<Ok, Error>`
- map types and struct types as Rust structs
- tagged tuple unions as Rust tuple enums

`RustQ.Meta.Lower` currently supports:

- assignments, returns, `case`, `if`
- `Option`, `Result`, and `NifResult` return wrapping in final return context
- aliases, remote calls, method calls, local calls
- mutable-reference inference from `mut_ref/1`
- pattern lowering for wildcard, literals, options, ok/error, tuples, struct
  tuple enum patterns, and atom guards
- semantic `expr!`, `pat!`, `stmt!`, `arm!` and raw escape helpers

### Self-hosted native AST decoder generation

`RustQ.NativeCodegen` now generates native AST decoder support using a mix of:

- `RustQ.Rust.AST.Builder` for module structure and dispatch
- `defrust` modules for field extraction and decoder bodies
- small native Rust primitive functions for Rustler/`syn` boundaries

Native Rust is split by responsibility:

- `lib.rs` — NIF entrypoints and module wiring
- `template.rs` — template/splice/bind AST mutation engine
- `parse.rs` — generic `syn` parsing primitives
- `parse_item.rs` — item/field/variant `syn` assembly
- `parse_type.rs` — type assembly
- `decode.rs` — Rustler term decode bridge, generic list/optional glue,
  literal handling, typed named-field collection, and calls into parse primitives
- `generated_ast.rs` — generated support, checked by `mix rustq.gen --check`

## Current dogfooding status

| Area | Status | Notes |
| --- | --- | --- |
| Template rendering | Native primitive | `template.rs` is appropriately handwritten; it manipulates `syn` ASTs directly. |
| NIF entrypoints | Native primitive | `lib.rs` is now thin and should stay that way. |
| Generic parsing | Native primitive | `parse_syn::<T>`, `parse_type`, `parse_path`, `parse_expr` are intentional primitives. |
| Item/type assembly | Native primitive, isolated | `parse_item.rs` and `parse_type.rs` centralize remaining `syn` assembly. |
| Rustler term helpers | Mostly dogfooded | `required_field`, `optional_map_get`, `atom_key`, `is_nil`, `struct_name`, `expect_struct` are `defrust`. |
| Dispatch | AST builder generated | Item/type/pat/stmt/expr dispatch is generated from schema. |
| Item decoders | Mostly dogfooded extraction | Field extraction is `defrust`; final assembly remains parse primitive. |
| Type decoders | Dogfooded extraction | Container assembly still often formats/parses type strings. |
| Expr/Pat/Stmt/Arm decoders | Mostly dogfooded | Semantic helpers cover most shapes; atom guard arms and let-pattern mutability remain primitive. |
| Collections | Generic primitive | `decode_list<T>` and `decode_optional_field<T>` avoid duplicated loops. |
| Struct/pattern fields | Improved | Native uses typed `NamedField<T>` rather than raw token vectors. |
| Literal decoding | Consolidated primitive | `LiteralTerm` centralizes literal term discrimination; expression/pattern choices still bridge to `syn`. |
| Testing | Stronger | Schema coverage uses behavioral validators; primitive boundary inventory tests exist. |

## Revised roadmap

### Phase 1 — Stabilize the AST/self-hosting contract

Goal: make it hard to accidentally regress into ad hoc string generation or new
native wrapper sprawl.

1. Expand primitive-boundary inventory tests so each native module has a clear
   expected responsibility:
   - `template.rs`: template mutation/parsing only
   - `parse*.rs`: `syn` parsing/assembly only
   - `decode.rs`: Rustler term decode and generic glue only
   - `lib.rs`: NIF entrypoints only
2. Add tests that fail if `generated_ast.rs` starts calling new `super::` helpers
   outside an explicit allowlist.
3. Keep `AGENTS.md` and this file aligned whenever a new primitive category is
   accepted.
4. Add a small changelog-like section to this plan for primitive additions and
   removals.

### Phase 2 — Type-directed lowering pass

Goal: replace scattered return/branch special cases with a reusable expected-type
lowering model.

1. Introduce an explicit lowering context struct or map containing:
   - expected return type
   - expression/statement/return position
   - known local variable types
   - branch target type
2. Route final returns, `case` arms, and `if` branches through one
   `lower_expected_expr/3`-style function.
3. Systematize wrapping rules:
   - `nil` => `None` for `Option<T>`
   - bare `value` => `Some(value)` for `Option<T>` in return/branch contexts
   - `:ok` => `Ok(())` for `NifResult<()>`
   - `{:ok, value}` / `{:error, value}` for `Result` and `NifResult`
   - atom errors in `NifResult` become `rustler::Error::RaiseAtom(...)`
4. Add tests for nested `case`/`if` returns across `Option`, `Result`, and
   `NifResult` rather than only final expression cases.

### Phase 3 — Grow the AST vocabulary where it removes primitives

Goal: reduce parsing/formatting boundaries by representing more Rust constructs
as typed AST nodes.

Candidate nodes/helpers, in priority order:

1. `TypeFormat` is **not** desired. Instead add real type AST support for:
   - generic path segments (`Option<T>`, `Result<T, E>`, `Vec<T>` without string
     formatting)
   - lifetimes on references and paths as first-class values
2. Function inputs / typed args as AST nodes to reduce `parse_item_function`
   assembly complexity.
3. Attribute/derive nodes to reduce `decode_derive` parsing.
4. Struct field value and pattern field nodes on the Elixir AST side, matching
   native `NamedField<T>` semantics.
5. Optional support for assignment statements, `for`/iterator loops, and early
   `return` only if needed to dogfood current native decode helpers.

Every new node must update:

- `RustQ.Rust.AST` type union and `__rustq_ast_modules__/0`
- builder support where useful
- native dispatch/decoder generation
- behavioral sample in `test/support/rustq_ast_samples.ex`
- primitive-boundary expectations if it removes or adds native code

### Phase 4 — Dogfood remaining decode bridge clusters

Goal: shrink `decode.rs` without adding trivial wrappers.

Likely dogfood candidates once the lowering language can express them cleanly:

1. `path_parts/1` and `decode_lifetime_list/1`
   - needs list map/join or a generic native string-list helper.
2. `keyword_args/1`
   - needs decoding of tuple lists and type-directed element mapping.
3. `decode_vis/1`
   - can move to `defrust` once visibility construction has a typed AST or a
     generic parse primitive call from semantic forms.
4. `decode_derive/1`
   - should wait for typed attribute/derive AST support.
5. `decode_literal_expr/1` / `decode_pat_literal_value/1`
   - either stay as one literal primitive or move after literal-term pattern
     matching is expressible without awkward Rustler calls.

Do **not** dogfood by creating one Rust helper per expression/pattern shape.

### Phase 5 — Strengthen `@type`/schema generation

Goal: make `@type` a credible source for Rust/Rustler surfaces, not just a demo.

1. Add more tests for:
   - nested maps
   - optional map fields
   - struct types with lifetimes
   - tuple enum unions with multiple variants
   - atom enum decoders with invalid atom behavior
2. Improve field decoder generation to reuse RustQ's own helper vocabulary rather
   than embedding ad hoc method chains.
3. Define the boundary between `RustQ.Meta.Type` and `RustQ.Rustler.Schema`:
   - either keep them separate with clear use cases
   - or plan a migration path so one schema model can feed both public Rustler
     helpers and defrust-generated native code.
4. Decide how generic `@type t(a)` aliases should map to Rust generics before
   broadening public promises.

### Phase 6 — Unify AST renderer behavior and fallback policy

Goal: make native AST rendering the primary path and fallback rendering an
explicit development aid.

1. Keep `AST.render_*_native` as the normal path for generated code.
2. Add focused tests that fallback renderers match native rendering for supported
   nodes where exact behavior matters.
3. Audit fallback renderers for known mismatches, such as integer suffixes from
   `syn`/Rustler decoding versus Elixir fallback rendering.
4. Decide whether unsupported native render failures should remain silent fallback
   or become explicit in stricter test/config modes.

### Phase 7 — Public API integration and documentation

Goal: make the experimental surface understandable without destabilizing the
stable template API.

1. Keep `README.md` clear that `defrust` is experimental.
2. Add focused docs/examples for:
   - valid-Elixir expression subset
   - semantic helpers vs raw escapes
   - `Super.*` primitive boundaries
   - `@type`-driven enum/struct generation
3. Add `mix rustq.gen` examples using `from_module My.Generated` once that path
   is robust enough for external users.
4. Avoid documenting internals like `RustQ.NativeCodegen.*` as public API.

## Near-term execution order

The next practical sequence should be:

1. Add a `super::` primitive allowlist test for generated native support.
2. Refactor `RustQ.Meta.Lower` around an explicit expected-type/context lowering
   helper.
3. Add nested branch tests for `Option`, `Result`, and `NifResult`.
4. Add real generic type AST support so `Option`, `Result`, `Vec`, and path
   generics no longer format strings in generated Rust.
5. Move type container decoding away from `format!(...)` + `parse_type` toward
   typed AST or token construction.
6. Decide whether `path_parts`/`decode_lifetime_list` should be dogfooded or
   consolidated as one generic string-list primitive.
7. Revisit public docs once the lowering/context refactor is stable.

## Verification gates

Use these targeted gates while working on this plan:

```sh
PATH="$HOME/.cargo/bin:$PATH" mix rustq.gen --check
~/.cargo/bin/cargo check --manifest-path native/rustq_nif/Cargo.toml
PATH="$HOME/.cargo/bin:$PATH" mix test test/rustq/ast test/rustq/native_codegen test/rustq/meta test/rustq/config
```

Before release or broad public-facing changes, run the full CI alias or its
components with Cargo resolved through `~/.cargo/bin` to avoid local shim issues.
