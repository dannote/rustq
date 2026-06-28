# Using RustQ Well

RustQ is for building readable Elixir↔Rust bridges. It gives you Rusty-Elixir,
`defrust`, RustQ AST, Rust source introspection, and generator validation so that
bridge code remains understandable as it grows.

RustQ also ships an agent skill file, `SKILL.md`, in the Hex package and source
repository. On HexDocs it is available at
[`https://rustq.hexdocs.pm/skill.md`](https://rustq.hexdocs.pm/skill.md). If you
use a coding agent to start a RustQ bridge, port existing bindings, or maintain a
RustQ-powered generator, give the agent `SKILL.md` before it writes code. The
skill is the short operational version of this guide.

The goal is not to move Rust string concatenation from `.rs` files into `.ex`
files. The goal is to use Elixir as a semantic metaprogramming language for Rust
bridges.

## The authoring ladder

Before writing generated Rust as a string, ask:

> Can this be valid Elixir, `defrust`, an ordinary Elixir macro, RustQ AST, or
> metadata inferred from Rust/source schemas instead?

Use this order:

1. `defrust` for implementation logic
2. ordinary Elixir macros for reusable Rusty-Elixir fragments
3. RustQ AST/builders for generated structure
4. Rust/Syn/schema/type introspection for metadata
5. tiny raw escapes only where RustQ lacks a representation

## `defrust` first

A `defrust` function is ordinary Elixir-shaped source that lowers to Rust:

```elixir
defmodule MyApp.Native.Generated do
  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec read_guid(R.mut_ref(Decoder.t())) :: R.nif_result(Guid.t())
  defrust read_guid(decoder) do
    session_id = decoder.read_var_uint()
    local_id = decoder.read_var_uint()
    {:ok, Guid.new(session_id, local_id)}
  end
end
```

When RustQ has callable metadata for the decoder methods and the function return
type is `NifResult<Guid>`, it can infer propagation and render the fallible calls
with `?`.

## Inference is a feature, not a trick

Older Rusty-Elixir code often used `unwrap!` everywhere to spell Rust `?`.
Current RustQ can infer many propagation sites.

### Return-position propagation

```elixir
@spec maybe_path() :: R.option(Path.t())
defrust maybe_path() do
  find_path()
end
```

If `find_path/0` is known to return `Option<Path>`, RustQ can propagate/shape the
return according to the expected return type.

### Argument propagation

```elixir
@spec decode_color(R.term()) :: R.nif_result(Color.t())
defrust decode_color(term) do
  value = decode_as!(term, R.u32())
  {:ok, Color.from_argb(255, 0, 0, value)}
end

@spec stroke(R.term(), R.slice({R.atom(), R.term()})) :: R.nif_result(Paint.t())
defrust stroke(term, opts) do
  stroke_paint(decode_color(term), 1.0, opts)
end
```

If `stroke_paint/3` expects a `Color` and returns `NifResult<Paint>`, RustQ can
render `decode_color(term)?` and propagate the final call.

### Downstream local inference

RustQ can infer the expected type of a binding from later uses:

```elixir
@spec draw(R.term()) :: R.nif_result(R.unit())
defrust draw(term) do
  color = decode_color(term)
  canvas.draw_color(color)
  :ok
end
```

The later `draw_color/1` call can tell RustQ that `color` should be the unwrapped
`Color`, not `NifResult<Color>`.

### When to use `unwrap!`

Use `unwrap!` only when you intentionally need to force `?` and RustQ cannot infer the propagation yet.

Before reaching for it, check whether the callable is available from:

- a local `@spec`
- a configured `callable_modules` module
- configured `rust_sources`
- configured `rust_packages`
- a known receiver type and method lookup
- an expected argument or return type

If a fallible call is a method on a Rust type, read the Rust source that defines the method and expose it to RustQ before assuming inference is impossible.

```elixir
value = unwrap!(legacy_decoder(term))
```

Do not use it reflexively around every fallible call. Prefer giving RustQ enough metadata to infer. If metadata is available but RustQ still cannot infer, treat that as a RustQ improvement candidate rather than normal downstream style.

Use `ok_or!` for explicit `Option<T>` to `Result`/`NifResult` conversion:

```elixir
@spec shader(R.ref(Paint.t())) :: R.nif_result(Shader.t())
defrust shader(paint) do
  ok_or!(paint.shader(), badarg())
end
```

## Feed RustQ real Rust metadata

Configure RustQ with real Rust sources and packages instead of copying Rust APIs
into Elixir:

```elixir
defmodule MyApp.Native.Generated do
  use RustQ.Meta,
    rust_sources: ["native/my_app_nif/src/helpers.rs"],
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

RustQ parses functions, impl methods, aliases, argument types, and return types through `RustQ.Syn`/binding metadata and uses that information while lowering.

For example, if generated code calls a downstream Rust `Decoder` method such as `decoder.read_var_int64()`, the right first step is to expose the `Decoder` implementation through `rust_sources` or equivalent callable metadata. Do not retype the method signature into an ad hoc Elixir table, and do not hide missing metadata behind `unwrap!`, verbose `case` propagation, or trivial wrappers.

## Do not paper over missing metadata with trivial wrappers

A wrapper that only calls one Rust method and returns unit is usually a smell if it exists only because RustQ cannot infer propagation:

```elixir
# Avoid this as a metadata workaround.
@spec skip_int64(R.mut_ref(R.path(:Decoder, R.lifetime(:_)))) :: R.nif_result(R.unit())
defrust skip_int64(decoder) do
  unwrap!(decoder.read_var_int64())
  :ok
end
```

First make the underlying Rust method visible through `rust_sources`, `rust_packages`, or `callable_modules`, or improve RustQ inference. Keep wrappers when they encode real bridge semantics or provide a stable function pointer shape, but do not use them to avoid reading the actual Rust API.

## Prefer recursion and reducers over Rusty exits

Rust has `return`, `loop`, `break`, and `continue`. RustQ has internal AST nodes
for them. That does not mean product bridge code should be written in that style.

Prefer recursion for small state machines:

```elixir
@spec skip_many(R.mut_ref(Decoder.t()), R.u32()) :: R.nif_result(R.unit())
defrust skip_many(decoder, remaining) do
  if remaining == 0 do
    :ok
  else
    skip_one(decoder)
    skip_many(decoder, remaining - 1)
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

Reach for `return!` only when the early-exit shape is genuinely the clearest low-level Rust primitive.

## Normal Elixir macros are the composition layer

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

RustQ expands ordinary Elixir macros before lowering. Use that instead of
building a separate Rust string DSL.

## Typespecs are the signature source of truth

Prefer ordinary Elixir and remote types where possible:

```elixir
@spec draw(
        R.ref(SkiaSafe.Canvas.t()),
        GeneratedOpts.CircleOpts.t(R.lifetime(:a)),
        R.slice({R.atom(), R.term()})
      ) :: R.nif_result(R.unit())
```

Use `RustQ.Type` for Rust-specific forms:

- `R.ref/1`, `R.mut_ref/1`, `R.slice/1`
- `R.u32()`, `R.i64()`, `R.f32()`, etc.
- `R.nif_result/1`, `R.result/2`, `R.option/1`, `R.vec/1`
- `R.lifetime/1`
- `R.raw/1` and `R.path/1,2` as low-level escapes

Avoid fake Elixir modules that exist only to force Rust paths.

## Semantic helpers and raw escapes

Use semantic helpers when you need Rust-shaped AST values inside Rusty-Elixir:

```elixir
expr!({:ok, value})
pat!({:ok, value})
stmt!(canvas.clear(color))
arm!({:ok, value}, value)
```

Use raw token escapes only when the semantic form does not exist yet:

```elixir
raw_expr!("unsafe { make_term(env, value) }")
```

If raw escapes spread or become repeated patterns, add a RustQ lowering rule,
AST node, or helper.

## RustQ AST for generated structure

Use builders for declarations and data-shaped Rust generation:

```elixir
alias RustQ.Rust
alias RustQ.Rust.AST.Builder, as: A

Rust.ast_item(A.const(:MAX_FIELDS, :usize, A.lit(128), vis: :pub))
```

If the AST cannot represent a needed construct, that is a RustQ feature request,
not permission to create large string templates.

## Explicit escape boundaries

RustQ has explicit escape boundaries. They exist so low-level integration points
are honest about being low-level:

- render/template entry points validate real Rust text
- `MacroItem`, `EscapeExpr`, and `TypeRaw` are explicit AST escape nodes
- some Rustler helpers accept caller-provided Rust expressions for advanced dispatch or defaults
- unsafe raw `NIF_TERM` helpers may need handwritten Rust because they sit at the Rustler wrapper boundary

Do not treat those boundaries as a normal generator style. Outside them, prefer
`defrust`, RustQ AST, or inferred metadata.

## Bad patterns

### String-built functions

```elixir
Rust.item([
  "fn decode_", name, "(decoder: &mut Decoder<'_>) -> NifResult<()> {\n",
  "    loop { ... }\n",
  "}\n"
])
```

This hides semantics and makes the generator hard to maintain.

### Duplicated metadata

```elixir
@primitive %{"uint" => "decoder.read_var_uint()?"}
@primitive_decoders [{"uint", :read_var_uint, []}]
```

Use one source of truth and derive the other forms.

### Rewriting Rust metadata by hand

If Rust owns the type/function/method, parse the Rust. Do not maintain an Elixir
shadow registry unless there is no better source.

## Porting existing Rustler bindings

1. Keep clear domain Rust as Rust.
2. Move repetitive NIF glue, decoders, option handling, and helper dispatch into
   `defrust` or RustQ AST.
3. Configure `rust_sources`/`rust_packages` before duplicating signatures.
4. Use `callable_modules` to reuse metadata from generated RustQ modules.
5. Generate via `rustq.exs`; check freshness in CI.
6. Run generated Rust through format/check/clippy.

## Dogfooding and downstream packages

The same rules apply more strictly inside RustQ and RustQ-powered generators:

- grow RustQ's semantic vocabulary before spreading string templates downstream
- keep generic machinery in generic packages and product semantics in product packages
- use behavioral tests and generated-output checks, not brittle policy grep tests
- treat raw escapes as candidates for future RustQ support

## API references

Useful modules to read in HexDocs/source:

- `RustQ.Meta`
- `RustQ.Type`
- `RustQ.Meta.Lower`
- `RustQ.Meta.Inference`
- `RustQ.Binding.Callable`
- `RustQ.Binding.Source`
- `RustQ.Binding.Index`
- `RustQ.Syn`
- `RustQ.Syn.Index`
- `RustQ.Rust.AST.Builder`
- `RustQ.Rust.AST.PatternBuilder`
- `RustQ.Rust.AST.TypeBuilder`
- `RustQ.Rustler`
- `RustQ.Rustler.Schema`

## Verification

- `mix ci`
- `mix rustq.gen --check`
- `cargo fmt --check`
- `cargo check`
- `cargo clippy -- -D warnings`
- downstream dogfood for shared generator changes

Generated Rust being Clippy-clean is necessary. It is not sufficient. The Elixir
that generates it should also be readable and beautiful.
