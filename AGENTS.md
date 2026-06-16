# Agent Guidelines for RustQ

## Rusty Elixir / AST-first discipline

When adding or changing Rust generation in this repository, always try to express the work through RustQ itself before falling back to raw Rust strings.

Preferred order:

1. **Use valid Elixir + `defrust` when possible**
   - Prefer ordinary Elixir syntax, pattern matching, calls, and `@spec`/`@type` driven lowering.
   - Do not introduce fake Rust syntax into Elixir.

2. **Use `RustQ.Rust.AST.Builder` for generated Rust structure**
   - Prefer helpers like `A.block`, `A.match`, `A.arm`, `A.if_expr`, `A.call`, `A.method`, `A.path`, `A.const`, `A.module`, etc.
   - Generated functions, dispatch tables, structs, modules, constants, and helper bodies should be AST-backed whenever possible.

3. **Add missing AST nodes/helpers instead of writing Rust strings**
   - If generation needs a Rust construct that RustQ cannot represent yet, first consider adding an AST node and native decoder/rendering support.
   - Keep growing the AST vocabulary rather than accumulating ad hoc string templates.

4. **Use raw Rust strings only as isolated escape hatches**
   - Acceptable examples: `AST.MacroItem` for macro invocations such as `rustler::atoms!`.
   - If a string fallback is used, keep it local and treat it as a candidate for future AST support.

5. **Schema/typespecs are the source of truth**
   - Prefer `defstruct`, `@type t`, and RustQ AST schema introspection over parallel hand-written schema maps.
   - Avoid duplicating field/type/category metadata unless there is no better source.

Before writing generated Rust as a string, ask:

> Can this be valid Elixir, `defrust`, or `RustQ.Rust.AST.Builder` instead?

If yes, use that path.
