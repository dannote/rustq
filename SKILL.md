---
name: rustq
summary: Build readable Elixir↔Rust bridges with RustQ in new NIF projects, ports of existing bindings, and code generators. Use Rusty-Elixir/defrust, inference, Rust source metadata, Elixir macros, and RustQ AST before raw Rust strings.
---

# RustQ Skill

Use this skill when starting a RustQ-powered NIF/bridge, porting existing Rustler bindings, adding generated Rust to an Elixir project, or working on RustQ itself.

RustQ's goal is a readable and maintainable Elixir↔Rust bridge. Generated Rust should be understandable through the Elixir that produced it. Do not turn RustQ projects into cryptic string emitters.

Full guide: https://rustq.hexdocs.pm/using-rustq-well.md

## First principles

1. **Write bridge behavior as Rusty-Elixir.** Prefer `defrust` functions with real `@spec`s.
2. **Let RustQ infer.** Do not sprinkle `unwrap!` everywhere. RustQ can infer many `?` propagations from return types, argument types, receiver types, and Rust source callable metadata.
3. **Use Elixir metaprogramming.** Use ordinary `defmacro`, `quote`, `unquote`, pattern matching, recursion, and schema transforms.
4. **Infer from Rust/source schemas.** Use `RustQ.Syn`, `rust_sources`, `rust_packages`, and `callable_modules` instead of hand-copying Rust APIs.
5. **Use RustQ AST/builders for generated structure.** If a construct is missing, prefer adding RustQ support over writing a large string template.
6. **Keep raw Rust strings tiny and local.** Macro invocations and unavoidable syntax escapes are fine; large generated functions as strings are not.

## Starting point for a new bridge

```elixir
defmodule MyApp.Native.Generated do
  use RustQ.Meta,
    rust_sources: ["native/my_app_nif/src/helpers.rs"]

  alias RustQ.Type, as: R

  @spec decode_color(R.term()) :: R.nif_result(R.raw(:Color))
  defrust decode_color(term) do
    value = decode_as!(term, R.u32())
    {:ok, Color.from_argb(255, 0, 0, value)}
  end

  @spec draw(R.mut_ref(Canvas.t()), R.term()) :: R.nif_result(R.unit())
  defrust draw(canvas, term) do
    color = decode_color(term)
    canvas.draw_color(color)
    :ok
  end
end
```

If RustQ knows `decode_color/1` returns `NifResult<Color>` and `draw_color/1` expects `Color`, it can lower the call as `decode_color(term)?` in the argument position. You do not need to write `unwrap!` just to force `?`.

## Prefer inference over `unwrap!`

`unwrap!` still exists as an explicit `?` escape hatch, but it should not be the default style for every fallible call.

Prefer this when callable metadata is available:

```elixir
@spec draw(R.term(), R.slice({R.atom(), R.term()})) :: R.nif_result(R.unit())
defrust draw(term, opts) do
  stroke_paint(decode_color(term), 1.0, opts)
  :ok
end
```

RustQ can infer propagation from:

- return-position expected wrappers (`NifResult<T>`, `Result<T, E>`, `Option<T>`)
- argument types from local `@spec`s
- argument types from `callable_modules`
- Rust free functions and impl methods parsed from `rust_sources` / `rust_packages`
- receiver method calls when the receiver type is known
- downstream uses of previously-bound locals
- vector pushes and iterator-like argument expectations in supported cases

Use `unwrap!` when you genuinely need to force propagation and RustQ cannot infer it yet:

```elixir
@spec decode_alpha(R.term()) :: R.nif_result(R.u8())
defrust decode_alpha(term) do
  value = decode_as!(term, R.u32())
  {:ok, cast(value, R.u8())}
end
```

Use `ok_or!` for explicit `Option<T>` to `Result`/`NifResult` boundaries:

```elixir
@spec shader(R.ref(Paint.t())) :: R.nif_result(Shader.t())
defrust shader(paint) do
  ok_or!(paint.shader(), badarg())
end
```

## Use Rust source metadata

Do not retype Rust APIs into Elixir registries when RustQ can read them.

```elixir
defmodule MyApp.Native.Generated do
  use RustQ.Meta,
    rust_sources: [
      "native/my_app_nif/src/paint.rs",
      "native/my_app_nif/src/generated.rs"
    ],
    rust_packages: [{"skia-safe", manifest_path: "native/my_app_nif/Cargo.toml"}],
    callable_modules: [MyApp.Native.GeneratedEnums]

  alias RustQ.Type, as: R

  @spec run(R.mut_ref(Paint.t()), R.atom()) :: R.nif_result(R.unit())
  defrust run(paint, atom) do
    paint.set_stroke_cap(decode_cap(atom))
    :ok
  end
end
```

RustQ parses callable signatures and uses them for propagation/argument inference.
This is the preferred way to bridge existing Rust libraries.

## Use recursion and reducers instead of return/break-driven product code

RustQ has internal AST nodes for Rust `return`, `loop`, `break`, and `continue`, but bridge/generator code should usually be written as Elixir-shaped control flow.

Prefer recursion for small state machines:

```elixir
@spec skip_remaining(R.mut_ref(Decoder.t()), R.u32()) :: R.nif_result(R.unit())
defrust skip_remaining(decoder, remaining) do
  if remaining == 0 do
    :ok
  else
    skip_one(decoder)
    skip_remaining(decoder, remaining - 1)
  end
end
```

Prefer `for ..., reduce:` for accumulator loops:

```elixir
@spec validate_all(R.vec(Item.t())) :: R.nif_result(R.unit())
defrust validate_all(items) do
  for item <- items, reduce: :ok do
    :ok -> validate_item(item)
  end
end
```

Use `return!`, `break`, and `continue` only when modelling an inherently Rusty low-level primitive or RustQ internals. They should be unusual in downstream product generators.

## Use ordinary Elixir macros for reusable Rusty-Elixir

```elixir
defmacro with_saved_canvas(do: body) do
  quote do
    var!(canvas).save()
    unquote(body)
    var!(canvas).restore()
  end
end

@spec draw(R.ref(Canvas.t())) :: R.nif_result(R.unit())
defrust draw(canvas) do
  with_saved_canvas do
    canvas.translate({1.0, 2.0})
  end

  :ok
end
```

RustQ expands normal Elixir macros before lowering. Use that power instead of generating Rust strings.

## Use the supported Rusty-Elixir surface

Common supported forms include:

- `@spec` / `@type` driven function signatures
- ordinary assignments (`let`) and inferred mutability when later assigned
- `case`, `if`, `with`, guards, tuple patterns, `{:ok, value}`, `{:error, reason}`, `{:some, value}`, `:none`
- method calls, remote calls, local calls, aliases, pipelines
- `decode_as/2` and `decode_as!/2` for Rustler term decoding
- `ref/1`, `mut_ref/1`, `deref/1`, `cast/2`, `array/1`, `index/2`, `struct_literal/2`
- `expr!`, `pat!`, `stmt!`, and `arm!` for semantic Rust-shaped AST values authored as valid Elixir
- `raw_expr!`, `raw_pat!`, `raw_stmt!`, and `raw_arm!` only as explicit token escapes

## Types: prefer clear specs

Use ordinary Elixir and remote types first:

```elixir
@spec draw(R.ref(SkiaSafe.Canvas.t()), GeneratedOpts.CircleOpts.t(R.lifetime(:a))) ::
        R.nif_result(R.unit())
```

Use `RustQ.Type` (`alias RustQ.Type, as: R`) for Rust-specific precision:

- `R.ref/1`, `R.mut_ref/1`, `R.slice/1`
- fixed-width numbers: `R.u32()`, `R.i64()`, `R.f32()`
- `R.nif_result/1`, `R.result/2`, `R.option/1`, `R.vec/1`
- `R.lifetime/1`
- `R.raw/1` and `R.path/1,2` as low-level escapes

Do not invent fake Elixir modules solely to spell Rust paths.

## AST/builders for generated structure

When generating Rust declarations, prefer RustQ AST/builders:

```elixir
alias RustQ.Rust
alias RustQ.Rust.AST.Builder, as: A

Rust.ast_item(A.const(:MAX_FIELDS, :usize, A.lit(128), vis: :pub))
```

If AST/native rendering rejects a shape you need, that is usually a RustQ capability gap. Add the missing node/decoder/rendering support rather than falling back to a giant template.

## Raw Rust strings: last resort

Acceptable:

```elixir
Rust.ast_item(A.macro_item("rustler::atoms! { ok, error }"))
```

Not acceptable as normal style:

```elixir
Rust.item([
  "fn decode_", name, "(decoder: &mut Decoder<'_>) -> NifResult<()> {\n",
  "    loop { ... }\n",
  "}\n"
])
```

If a raw escape grows beyond a small syntax boundary, stop and add a semantic RustQ capability.

## Porting checklist

When porting existing bindings:

1. Keep clear handwritten Rust as Rust.
2. Move repetitive bridge glue to `defrust` or AST-backed generation.
3. Configure `rust_sources` / `rust_packages` before duplicating Rust signatures.
4. Replace metadata registries with inference from Rust/schema/typespecs.
5. Add `rustq.exs`, generate checked-in Rust if needed, and enforce `mix rustq.gen --check`.
6. Run generated Rust through `cargo fmt`, `cargo check`, and `cargo clippy -- -D warnings`.

## References

Read these in HexDocs/source when working with RustQ:

- `RustQ.Meta` — `defrust`, module options, Rusty-Elixir lowering entry point
- `RustQ.Type` — typespec vocabulary
- `RustQ.Rust.AST.Builder` — AST constructors
- `RustQ.Rust.AST.PatternBuilder` and `RustQ.Rust.AST.TypeBuilder`
- `RustQ.Syn` and `RustQ.Syn.Index` — Rust source introspection
- `RustQ.Binding.Callable`, `RustQ.Binding.Source`, `RustQ.Binding.Index` — callable metadata/inference inputs
- `RustQ.Rustler` and `RustQ.Rustler.Schema` — Rustler helper generation
- `RustQ.Meta.Lower` and `RustQ.Meta.Inference` — current lowering/inference behavior
- `guides/using-rustq-well.md` — expanded guide with examples

## Verification

For non-trivial changes:

- `mix ci`
- `mix rustq.gen --check` where applicable
- downstream dogfood CI when changing shared generators
- generated Rust: `cargo fmt --check`, `cargo check`, `cargo clippy -- -D warnings`
- compare generated size after the generator remains readable

Clippy-clean Rust is necessary, not sufficient. RustQ code should also be beautiful at the generator layer.
