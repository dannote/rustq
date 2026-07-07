# RustQ Roadmap — Next Generation

Strategic plan to take RustQ from v0.5.x ("Rusty Elixir MVP") to a polished,
powerful typed-macro metalanguage for Rust codegen.

State of this document reflects review on 2026-06-19 against `defrust-meta-mvp`
and the skia dogfood (`../skia_ex`).

## Where we are

- **Wave 1 is complete.** Semantic helpers lower through real RustQ AST,
  native AST rendering is mandatory, `strict_native_ast` is gone, and Skia has
  been validated against `semantic-escapes-ast` after the namespace cleanup.
- **Wave 2 is mostly complete.** Schema/native decoder/render coherence is
  tested from `AST.Schema.nodes()`, rendering/build/lowering failures now raise
  structured diagnostics, and tests mirror the source layout. The remaining Wave
  2 gap is a full golden lowering corpus.
- **Module structure has been cleaned up beyond the original roadmap.**
  `NativeCodegen` is now `Codegen`, external Rust metadata lives under
  `RustQ.Native.*`, Rustler helper modules are concept-oriented, `RustQ.Meta` is
  split into focused submodules, config state lives in `RustQ.Config.State`, and
  every module has real documentation instead of `@moduledoc false`.
- **Skia proves the dogfood.** `Skia.Codegen.Rusty.*` author drawing semantics
  in `defrust` + ordinary `quote`/`unquote` with **zero** `expr!`/`pat!`/`stmt!`/
  `arm!`/`raw_*` escapes in semantic bodies. ~3.3k of 4k native lines are
  generated; CI gates on `mix rustq.gen --check`. The ownership boundary (Skia
  owns semantics, RustQ owns lowering) holds in practice.
- **Discipline is codified** in `AGENTS.md`; architecture enforcement belongs in
  Reach/ExDNA/Credo/custom linting or schema-driven behavioral tests, not ad hoc
  ExUnit source-grep tests.

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
| I | No native-render dogfood gate across RustQ + skia proving every lowered body renders through native AST without fallback. | `RustQ.Native.render_ast/1` is mandatory in RustQ; skia still needs an explicit cross-project gate | Wave 1 / skia follow-up |
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

1. **Collapse `semantic_expr`/`semantic_pat` into direct AST lowering.** ✅ Done.
   `expr!`/`pat!`/`stmt!`/`arm!` reuse direct lowering; only `raw_*` remains as a
   token-level escape hatch. Closes gap A.
2. **Require native AST rendering.** ✅ Done. No `strict_native_ast` mode and no
   silent fallback: AST item rendering goes through `RustQ.Native.render_ast/1`.
   Closes gap B.
3. **Native-render dogfood gate in skia.** ✅ Done via cross-project validation
   on `rustq-semantic-escapes-validation`; Skia has been migrated to the new
   namespaces and validated against latest `semantic-escapes-ast`. Closes gap I.

> Note: the originally-proposed "rename `unwrap!` → `propagate!`" and "`let!`
> lowering" items are **superseded** by Wave 3 type-driven propagation
> inference, which treats the root cause (gap J) rather than the symptom.

## Wave 2 — Schema coherence & diagnostics (scaling safety)

Goal: make adding a node safe by construction; make failures legible.

4. **Schema ↔ renderer ↔ decoder ↔ lowering coherence test.** ✅ Mostly done.
   Coherence is derived from `AST.Schema.nodes()` for samples, schema fields,
   native dispatch coverage, and decoder coverage. Closes the practical half-wired
   node risk in gap C.
5. **Lowering golden corpus.** ❌ Remaining. `test/corpus/*.exs` → expected `.rs`,
   covering every documented construct; CI diffs rendered output. Turns anecdotal
   completeness into a measured surface. Closes gap E.
6. **Structured diagnostics.** ✅ Done for lowerer unsupported forms, defrust
   build failures, and native render failures with `RustQ.Diagnostic`. Closes
   gap H for the current failure paths.

## Wave 3 — `Syn`-driven bindings & type-driven lowering (the new power)

Goal: RustQ becomes compelling for *wrapping* crates, not just *authoring* new
ones; and Rusty Elixir reads as clean as the Rust it emits.

7. **`RustQ.Binding` adapter layer.** 🟡 Started. `RustQ.Binding.Callable`
   normalizes `RustQ.Syn.Function`, `RustQ.Syn.Method`, and
   `RustQ.Native.Descriptor` into callable metadata with `RustQ.Meta.Type`
   args/returns. `RustQ.Binding.Index` now provides local/target-qualified
   return-type lookup, and `RustQ.Meta.Lower` accepts callable metadata through
   its context. Remaining work: generate Rusty-Elixir-shaped lowering targets
   and wrappers from these callables. Closes gap D.
8. **Round-trip `Syn` ↔ `defrust` type specs.** 🟡 Started. `RustQ.Meta.Type.from_syn/1`
   and `RustQ.Spec.from_syn/1` now map structured `Syn.Type` metadata into
   `RustQ.Meta.Type` for common path/ref/option/result/tuple/slice/array/raw
   shapes. Remaining work: reverse mapping, richer lifetime/generic fidelity,
   and method-signature-level spec derivation. Prerequisite for item 9; closes
   gap D fully.
9. **Type-driven propagation inference (headline).** 🟡 Started. The lowerer now
   infers Rust `?` in return position, typed assignment/let RHS positions, and
   callable argument positions for local, remote, and typed receiver method calls
   when callable metadata says the nested call returns
   `Result<T, E>`/`NifResult<T>`/`Option<T>` and the expected type is `T`.
   Remaining work: broader local type propagation, project-wide/raw Rust helper
   callable metadata, external native method/function callable metadata, and Skia
   migration. Skia dogfood showed that raw helpers such as `stroke_paint` and
   external calls such as `Paint::set_*`/`ImageFilters::*` still require explicit
   `unwrap!` until their argument signatures are available to lowering. Closes
   gap J.
   Metric: ~0 explicit propagation operators in skia post-migration.
10. **Light borrow/`mut` model.** Carry lifetime/`mut` intent from `Syn` arg
    types into lowered bindings instead of pure heuristics. Not full borrowck —
    just "this arg is `&mut` so the binding is `mut_ref`". Closes gap F.

### Post-0.9.3 downstream adapter audit

Skia, Figler, and Kiwi Codec now dogfood released RustQ `~> 0.9.3` instead of
local path dependencies. A sweep of remaining `unwrap!`, `ref(...)`,
`mut_ref(...)`, `.as_ref()`, `.as_slice()`, and `.as_deref()` sites found that
most remaining occurrences are deliberate boundaries rather than easy cleanup:

- **Type metadata:** `R.ref(...)` and `R.mut_ref(...)` in specs/types remain the
  correct way to express Rust references in Elixir typespecs.
- **Stored/lifetime borrows:** Skia `SaveLayerRec` needs `bounds.as_ref()`
  because `SaveLayerRec::bounds(&'a Rect)` stores the reference; borrowing an
  owned `Rect` inside a match arm is invalid.
- **Indexed storage borrows:** Figler `ref(index(scene.nodes, node_index))`
  avoids moving out of indexed scene storage. This should stay explicit unless
  RustQ learns a borrow-preserving indexed-access model.
- **Slice/option adapter APIs:** Skia gradient colors, positions,
  path-effect intervals, shader matrices/tile rects, and similar Rust APIs
  require exact slice/option-reference adapter shapes.
- **Term map arrays:** Figler/Kiwi Codec `ref(keys)` / `ref(values)` around
  generated temporary arrays are API-bound helper calls. Future cleanup would
  need richer helper callable metadata, not blind removal.
- **Entrypoint propagation leftovers:** Skia `CommandDomain` still has macro-
  generated `unwrap!(decode_args/1)`, `unwrap!(decode_opts/1)`, and generated
  opts decoder calls. These are plausible future cleanup candidates because they
  are local helper calls, but they should be covered by a focused corpus fixture
  before migration.

Future inference work should target one of the explicit "future candidate"
classes above with corpus coverage first. Do not chase the lifetime/API-required
adapter sites as cosmetic noise.

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
