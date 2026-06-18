# Agent Guidelines for RustQ

## Rusty Elixir / AST-first discipline

When adding or changing Rust generation in this repository, always try to express the work through RustQ itself before falling back to raw Rust strings.

Preferred order:

1. **Use valid Elixir + `defrust` when possible**
   - Prefer ordinary Elixir syntax, pattern matching, calls, normal Elixir macros, and `@spec`/`@type` driven lowering.
   - Use ordinary external remote types in specs for Rust paths where possible (for example `GeneratedOpts.OvalOpts.t(R.lifetime(:a))` -> `generated_opts::OvalOpts<'a>`); keep `R.path` as a low-level escape hatch.
   - Do not introduce fake Rust syntax into Elixir.

2. **Use `RustQ.Rust.AST.Builder` for generated Rust structure**
   - Prefer helpers like `A.block`, `A.match`, `A.arm`, `A.if_expr`, `A.call`, `A.method`, `A.path`, `A.const`, `A.module`, etc.
   - Generated functions, dispatch tables, structs, modules, constants, and helper bodies should be AST-backed whenever possible.

3. **Add missing AST nodes/helpers instead of writing Rust strings**
   - If generation needs a Rust construct that RustQ cannot represent yet, first consider adding an AST node and native decoder/rendering support.
   - Keep growing the AST vocabulary rather than accumulating ad hoc string templates.

4. **Use semantic Rusty-Elixir helpers before raw strings**
   - Compose repeated Rusty-Elixir bodies with ordinary Elixir `defmacro`, `quote`, and `unquote`; do not invent RustQ-specific quoting unless normal Elixir macros are insufficient.
   - `expr!(...)` lowers valid Rusty-Elixir values such as `:ok` and `{:ok, value}` to a `syn::Expr`.
   - `Super.foo(...)` in `defrust` intentionally lowers to a Rust parent-module call such as `super::foo(...)`.
   - `Atoms.fill()`-style plural aliases automatically lower to snake-case Rust modules such as `atoms::fill()`; do not add fake `defrustmod` declarations for externally-owned modules.
   - `raw_expr!(...)`, `raw_pat!(...)`, `raw_stmt!(...)`, and `raw_arm!(...)` are explicit Rust token escape hatches that lower through parser helpers.

5. **Use raw Rust strings only as isolated escape hatches**
   - Acceptable examples: `AST.MacroItem` for macro invocations such as `rustler::atoms!`.
   - If a string fallback is used, keep it local and treat it as a candidate for future AST support.

6. **Schema/typespecs are the source of truth**
   - Prefer `defstruct`, `@type t`, and RustQ AST schema introspection over parallel hand-written schema maps.
   - Avoid duplicating field/type/category metadata unless there is no better source.

7. **Self-hosting invariants**
   - Do not introduce trivial Rust wrapper functions for semantic forms already written in `defrust`.
   - Do not add parallel constructor registries or data tables for `expr!`, `pat!`, `stmt!`, or `arm!` shapes.
   - Extend `RustQ.Meta.Lower` and existing RustQ AST nodes before adding new primitive Rust helpers.
   - Funnel token-only semantic escapes through generic primitives such as `parse_syn::<T>(quote!(...))` rather than one helper per shape.
   - Every new `RustQ.Rust.AST.Schema` node must get behavioral native rendering coverage.

Before writing generated Rust as a string, ask:

> Can this be valid Elixir, `defrust`, or `RustQ.Rust.AST.Builder` instead?

If yes, use that path.
