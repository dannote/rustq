# RustQ Roadmap — Next Generation

Strategic plan to take RustQ from v0.5.x ("Rusty Elixir MVP") to a polished,
powerful typed-macro metalanguage for Rust codegen.

State of this document reflects review on 2026-06-19 against `defrust-meta-mvp`
and the skia dogfood (`../skia_ex`).

## Where we are

- **Two authoring surfaces, one strategic direction.** `defrust` Rusty Elixir
  (`@spec`/`@type` + ordinary macros + bodies → `RustQ.Rust.AST` → native NIF
  render) is the direction. Templates/`~R`/builders/`RustQ.Rustler.Schema` are
  stable-but-legacy.
- **Lowering is genuinely AST-native** for the mainstream constructs: 77
  `defnode`s across items/stmts/exprs/types/pats, real structs emitted by
  `Meta.Lower`, native rendering through `RustQ.Native.render_ast` with a
  `strict_native_ast` switch.
- **Skia proves the dogfood.** `Skia.Codegen.Rusty.*` author drawing semantics
  in `defrust` + ordinary `quote`/`unquote` with **zero** `expr!`/`pat!`/`stmt!`/
  `arm!`/`raw_*` escapes in semantic bodies. ~3.3k of 4k native lines are
  generated; CI gates on `mix rustq.gen --check`. The ownership boundary (Skia
  owns semantics, RustQ owns lowering) holds in practice.
- **Discipline is codified** in `AGENTS.md` and lightly enforced by
  `architecture_test.exs`.

## Gaps (evidence → fix)

| # | Gap | Evidence | Addressed in |
|---|-----|----------|--------------|
| A | `semantic_expr`/`semantic_pat` build Rust source strings that round-trip through `parse_syn`, even for shapes the mainstream `lower_expr` already emits as AST nodes. Parallel path; violates AGENTS #7. | `lib/rustq/meta/lower.ex:564–700`; skia never uses `expr!`, so this path is undertested | Wave 1 |
| B | Silent render fallback unless `strict_native_ast: true`. A render gap can emit subtly wrong Rust in real builds. | `lib/rustq/rust/ast/render.ex:106–117` | Wave 1 |
| C | No coherence guarantee between `defnode` ↔ Elixir renderer ↔ native decoder ↔ `Meta.Lower`. A new node must be wired in ~4 places with no check. Biggest scaling risk. | `ast/schema.ex` + `decoders/*.ex` | Wave 2 |
| D | No `RustQ.Syn` → Rusty-Elixir binding adapter. Wrapping a crate means hand-authoring every `defrust` shell. | `skia/codegen/skia_safe.ex` + `commands/*` | Wave 3 |
| E | Lowering completeness is anecdotal. `lower.ex` raises `unsupported` in several spots; no golden corpus. | grep `unsupported` in `lower.ex` | Wave 2 |
| F | Mutability/lifetime inference is heuristic; lifetimes come only from `R.lifetime(:a)` in specs, never inferred in bodies. | `lower.ex:790–845` | Wave 3 |
| G | No crate-level manifest. `rustq.exs` is file-list-oriented; skia hand-rolls 19 targets via `generated_targets/0`. | `skia/codegen.ex:11–60` | Wave 4 |
| H | Diagnostics are bare `ArgumentError`s. No spans, no offending-node reporting. | `lower.ex` raises | Wave 2 |
| I | No strict-native dogfood gate. Architecture test only forbids a few string patterns. | `architecture_test.exs` | Wave 1 |
| **J** | **`unwrap!` noise.** ~190 uses in skia; the macro name is semantically wrong (`unwrap`/`unwrap()` means *panic* in both Rust and Elixir, but it generates `?` = *propagate*), and the `?` it spells is fully derivable from the called function's `@spec` return type vs the expected type at the call position. Author is forced to restate type information the compiler already has. | `grep -r unwrap! skia`; every decode helper has a `Result`/`Option` `@spec` | **Wave 3** |

## The headline insight: type-driven propagation inference

`unwrap!(expr) → expr?` is **syntax-to-syntax** lowering. Rust's `?` is
*mandatory* on the Rust surface because the compiler rejects
`let x = f()` when `f: -> Result<T>`. But that mandate does **not** exist at the
Elixir/meta layer: RustQ has the called function's return type (from `@spec`,
confirmed for every skia decode helper) and the expected type at the call
position. Whether `?` is needed is fully determined by those types. Forcing the
author to spell it is making them transcribe a Rust-language requirement that
RustQ could derive.

Lowering rule (target):

> Insert `?` at a call site iff the call's return type is
> `Result<_>`/`Option<_>`/`NifResult<_>` **and** the expected type at that
> position is the inner type.

Examples:

```elixir
# today (skia, ~166 of 190 sites)
matrix = unwrap!(optional_matrix_from_term(matrix_term))
tile_mode = unwrap!(GeneratedEnums.decode_tile_mode(tile_mode))

# after: identical generated Rust, no explicit operator
matrix = optional_matrix_from_term(matrix_term)
tile_mode = GeneratedEnums.decode_tile_mode(tile_mode)
```

```elixir
# stays silent — scrutinee expected as Result
case f(a) do
  {:ok, v} -> ...
  {:error, _} -> ...
end
```

This is *not* hairy type inference. It is the same check Rust's `?` desugaring
performs, moved to lowering time. It needs two pieces of plumbing, both of which
are Wave 3 prerequisites anyway:

1. **Called-function return types at lowering time.** For `defrust` helpers:
   available now via `@spec`. For **external** Rust calls
   (`skia_safe::Canvas::draw_rect`, `effect.find_uniform`): requires `RustQ.Syn`
   metadata wired into the lowering context — Wave 3 item 1.
2. **Expected-type propagation at lowering positions.** Extends the existing
   `infer_expr_type` (`lower.ex`) into a small bidirectional check — the same
   machinery as the light borrow/type model (Wave 3 item 3).

This is why propagation inference is **Wave 3**, not Wave 1: it depends on the
`Syn`-type plumbing. It is also the deliverable that makes Rusty Elixir read as
clean as the Rust it emits — which is the whole point of the metalanguage.

Honest readability tradeoff: Rust deliberately makes propagation visible. But in
the decode-block pattern that dominates skia, *every* line propagates, so
visibility carries no information — it is pure noise. The right boundary is:
infer by default; require an explicit `case` when you want to handle. That
matches how Elixir authors already think (`with`/`case` at boundaries,
straight-line elsewhere).

Metric: target **~0 explicit propagation operators in skia** after migration.

---

## Wave 1 — Consolidation & self-hosting (de-risk what exists)

Goal: remove the ways the "AST-native" story is quietly undermined by string
round-trips and silent fallbacks. Cheap, high-confidence.

1. **Collapse `semantic_expr`/`semantic_pat` into direct AST lowering.** Make
   `expr!`/`pat!`/`stmt!`/`arm!` pure Rusty-Elixir convenience wrappers that
   reuse the same `lower_expr` clauses — no `raw_expr("Ok(#{...})")` string
   building, no `parse_syn` round-trip for shapes that already have AST nodes.
   Keep `raw_expr!`/`raw_pat!`/`raw_stmt!`/`raw_arm!` as the *only* token-level
   escape, funneled through `parse_syn::<T>(quote!(...))`. Closes gap A.
2. **Make `strict_native_ast` the default in `mix ci`** (and skia's CI alias),
   opt-out for local dev. Closes gap B.
3. **Strict-native dogfood gate test.** Lower every `defrust` body in repo +
   skia and assert zero Elixir-render fallback paths fire. Closes gap I.

> Note: the originally-proposed "rename `unwrap!` → `propagate!`" and "`let!`
> lowering" items are **superseded** by Wave 3 type-driven propagation
> inference, which treats the root cause (gap J) rather than the symptom.

## Wave 2 — Schema coherence & diagnostics (scaling safety)

Goal: make adding a node safe by construction; make failures legible.

4. **Schema ↔ renderer ↔ decoder ↔ lowering coherence test.** For every
   `defnode`, assert: (a) Elixir `render_*` clause exists, (b) native decoder
   branch exists, (c) `Meta.Lower` has a lowering clause or explicitly defers to
   raw. Generate from `AST.Schema.nodes()` so a new node can't ship half-wired.
   Closes gap C.
5. **Lowering golden corpus.** `test/corpus/*.exs` → expected `.rs`, covering
   every documented construct; CI diffs rendered output. Turns anecdotal
   completeness into a measured surface. Closes gap E.
6. **Structured diagnostics.** Replace `ArgumentError` raises with a
   `RustQ.Diagnostic` carrying the offending Elixir AST node, span, and
   suggested construct. Closes gap H.

## Wave 3 — `Syn`-driven bindings & type-driven lowering (the new power)

Goal: RustQ becomes compelling for *wrapping* crates, not just *authoring* new
ones; and Rusty Elixir reads as clean as the Rust it emits.

7. **`RustQ.Binding` adapter layer.** Given a `RustQ.Syn.Method`/`Syn.Enum`/
   `Syn.Struct`, generate a Rusty-Elixir-shaped lowering target (call signature,
   arg decode, return wrap) instead of forcing hand-authoring. A wrapper project
   declares "expose `Canvas::draw_rect`" and gets the `defrust` shell for free,
   filling only the semantic body. Closes gap D.
8. **Round-trip `Syn` ↔ `defrust` type specs.** Map `Syn.Type` ↔ `RustQ.Type`
   bidirectionally so specs can be *derived* from upstream Rust signatures, with
   manual override where Rusty semantics differ. Prerequisite for item 9; closes
   gap D fully.
9. **Type-driven propagation inference (headline).** Infer `?` from
   called-function return type vs expected type at call position. Drop
   `unwrap!`/`propagate!`/`let!` as the default authoring form; keep an explicit
   operator only as a rare escape hatch for untyped/external calls (and even
   there, `raw_expr!`/`parse_syn` already covers it). Closes gap J. Metric:
   ~0 explicit propagation operators in skia post-migration.
10. **Light borrow/`mut` model.** Carry lifetime/`mut` intent from `Syn` arg
    types into lowered bindings instead of pure heuristics. Not full borrowck —
    just "this arg is `&mut` so the binding is `mut_ref`". Closes gap F.

## Wave 4 — Crate-level generation & ecosystem (polish & reach)

Goal: RustQ graduates from "a file generator" to "a crate generator" and proves
generality.

11. **`rustq.exs` crate manifest.** First-class `crate` blocks: multiple `.rs`
    outputs, `mod` declaration generation, `Cargo.toml` `[features]`/deps sync,
    content-hash incremental cache. Replaces skia's hand-rolled
    `generated_targets/0`. Closes gap G.
12. **`defrustmod` composition primitives.** `pub use` re-exports, `impl`
    grouping across modules, trait impl emission from specs.
13. **Second dogfood target beyond skia.** A smaller, different crate (e.g. a
    serde-like or wgpu wrapper) to pressure-test that the design generalizes
    past the drawing domain and that `Syn` adapters (Wave 3) actually pay off.
14. **Docs restructure.** Split README into a Rusty-Elixir guide (strategic
    surface) vs reference for templates/builders (legacy-but-supported). Publish
    the lowering grammar (constructs → Rust) generated from the Wave 2 corpus.

## Sequencing rationale

Waves 1–2 are cheap and remove the biggest risk: that the "AST-native" story is
quietly undermined by string round-trips and silent fallbacks, and that adding a
node can silently ship half-wired. Wave 3 is the differentiator — `Syn`-driven
binding adapters plus type-driven propagation inference are what make RustQ
compelling for *wrapping* crates and what make the authoring surface read as
clean as the Rust it emits. Wave 4 turns RustQ into a crate generator and proves
generality.
