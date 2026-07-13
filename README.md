# RustQ

RustQ helps Elixir projects generate Rust without building Rust strings by hand.
It parses real Rust, validates generated fragments, and lets Elixir act as a
macro language for Rust codegen.

RustQ now has two complementary authoring styles:

- **Rusty Elixir with `defrust`** — write Rust implementation logic as valid
  Elixir using `@spec`, `@type`, `defmacro`, `quote`, ordinary `case`, aliases,
  calls, and pattern matching. RustQ lowers that Elixir AST into Rust AST.
- **Real Rust templates and builders** — generate Rust from `.rs` templates,
  placeholders, Rust fragment builders, and Rustler helper generators.

The goal is not to embed Rust syntax in Elixir. The goal is to use Elixir as a
typed macro metalanguage for generating real Rust safely.

## Installation

Add RustQ to `mix.exs`:

```elixir
{:rustq, "~> 0.9", only: [:dev, :test], runtime: false}
```

RustQ compiles a Rustler NIF at generation time, so Rust/Cargo must be available
where `mix rustq.gen` or your own codegen task runs.

## Agent skill included

RustQ ships an agent-facing skill file at [`SKILL.md`](SKILL.md). If you use a
coding agent to start a RustQ project, port existing bindings, or maintain a
RustQ-powered generator, give the agent that file first. It summarizes RustQ's
ideology, authoring order, inference features, and anti-patterns.

The same guidance is published in HexDocs as
[`Using RustQ Well`](https://rustq.hexdocs.pm/using-rustq-well.md). For
source-derived Rustler exports, Elixir stubs, atoms, and term encoders, see
[`Generating Rustler Boundaries`](https://rustq.hexdocs.pm/rustler-generation.html).
The skill itself is also available at
[`https://rustq.hexdocs.pm/skill.md`](https://rustq.hexdocs.pm/skill.md).

## Choose an authoring style

| Need | Use |
| --- | --- |
| Write Rust implementation logic in Elixir | `RustQ.Meta.defrust` |
| Compose reusable Rusty-Elixir body fragments | ordinary Elixir `defmacro`, `quote`, and `unquote` |
| Generate from real `.rs` files | templates, `~R`, placeholders, `RustQ.render_file!/2` |
| Generate repetitive Rust declarations from data | `RustQ.Rust` builders or RustQ AST builders |
| Generate Rustler boilerplate | `RustQ.Rustler` helpers or `RustQ.Rustler.Schema` |
| Introspect existing Rust crates structurally | `RustQ.Syn` |
| Keep generated files checked in and fresh | `rustq.exs` plus `mix rustq.gen --check` |

## Rusty Elixir with `defrust`

`defrust` is the high-level user-facing Rusty-Elixir surface. It reads normal
Elixir `@spec` and `@type` declarations, expands ordinary Elixir macros, and
lowers the resulting valid Elixir body into RustQ's Rust AST.

Low-level bridges such as `RustQ.Meta.quoted` are internal escape hatches for
generators, not the normal authoring API.

A Rusty-Elixir implementation can look like this:

```elixir
defmodule MyApp.Native.GeneratedShapes do
  use RustQ.Meta

  alias RustQ.Type, as: R

  defmacro with_fill_paint(do: body) do
    quote do
      case opt_fill_paint(var!(raw_opts), Atoms.fill()) do
        {:some, var!(paint)} ->
          apply_blend_mode(var!(paint), var!(raw_opts))
          unquote(body)

        :none ->
          :ok
      end
    end
  end

  defmacro with_stroke_paint(width, do: body) do
    quote do
      case opt_color(var!(raw_opts), Atoms.stroke()) do
        {:some, var!(color)} ->
          var!(stroke_paint_value) = stroke_paint(var!(color), unquote(width), var!(raw_opts))
          unquote(body)

        :none ->
          :ok
      end
    end
  end

  @spec draw_circle_impl(
          R.ref(SkiaSafe.Canvas.t()),
          GeneratedOpts.CircleOpts.t(R.lifetime(:a)),
          R.slice({R.atom(), R.term()})
        ) :: R.nif_result(R.unit())
  defrust draw_circle_impl(canvas, opts, raw_opts) do
    center = Point.new(opts.x, opts.y)

    with_fill_paint do
      canvas.draw_circle(center, opts.radius, paint)
    end

    with_stroke_paint opts.stroke_width.unwrap_or(1.0) do
      canvas.draw_circle(center, opts.radius, stroke_paint_value)
    end

    :ok
  end
end
```

That is ordinary Elixir syntax. RustQ uses the typespec and lowering rules to
render Rust like:

```rust
fn draw_circle_impl<'a>(
    canvas: &skia_safe::Canvas,
    opts: generated_opts::CircleOpts<'a>,
    raw_opts: &[(Atom, Term<'a>)],
) -> NifResult<()> {
    // ... real Rust AST output ...
}
```

### Rusty-Elixir rules

The intended style is:

- use `@spec` as the function signature source of truth
- use ordinary Elixir `@type` declarations for Rust enums/structs/decoders when
  RustQ owns those shapes
- use ordinary external remote types for external Rust paths where possible:
  `SkiaSafe.Canvas.t()` renders as `skia_safe::Canvas`, and
  `GeneratedOpts.OvalOpts.t(R.lifetime(:a))` renders as
  `generated_opts::OvalOpts<'a>`
- use `RustQ.Type` (`alias RustQ.Type, as: R`) only where Elixir typespecs need
  Rust-specific precision: `R.ref/1`, `R.mut_ref/1`, `R.nif_result/1`,
  `R.unit/0`, `R.slice/1`, `R.term/0`, fixed-width numbers, lifetimes, options,
  results, and vectors
- use ordinary aliases and calls in bodies; plural module aliases such as
  `Atoms.fill()` render as snake-case Rust modules such as `atoms::fill()`
- use normal Elixir `defmacro`, `quote`, and `unquote` for reusable Rusty-Elixir
  fragments; RustQ expands those macros before lowering
- keep Rust-owned concepts in the Rust-owning project or crate; do not invent
  fake Elixir modules just to force a Rust path
- treat raw token escapes as last-resort escape hatches

`R.path/1,2` exists as a low-level escape hatch for Rust paths that cannot be
expressed cleanly as ordinary remote types. It should not be the default style.

### Rusty-Elixir body syntax

Current `defrust` lowering supports a growing valid-Elixir subset:

- ordinary assignment lowers to Rust `let`
- final expressions lower according to the `@spec` return type
- `:ok` under `R.nif_result(R.unit())` lowers to `Ok(())`
- `case` lowers to Rust `match`
- Option cases can be written as `{:some, value}` and `:none`
- Result cases can be written as `{:ok, value}` and `{:error, reason}`
- fallible calls in argument, return, case-scrutinee, `some(...)`, `decode_as!`,
  and many local-binding positions can infer Rust `?` from type metadata
- `unwrap!(expr)` explicitly spells Rust `expr?`; prefer inference when metadata
  is available
- `ok_or!(option_expr, error_expr)` spells Rust
  `option_expr.ok_or(error_expr)?`; use it for explicit `Option<T>` to
  `Result<T, E>` boundaries such as `ok_or!(paint.shader(), badarg())`
- `assign!(target, expr)` spells Rust assignment for explicit mutation, and
  `return!(expr)` spells early return
- `ref(expr)`, `mut_ref(expr)`, and `deref(expr)` explicitly spell Rust borrows
  and dereference; many ordinary calls infer borrows from expected argument types
- `decode_as(term, type)` and `decode_as!(term, type)` spell Rustler typed
  decode probes and required decodes
- `array([...])`, `index(collection, index)`, and `struct_literal(Path, fields)`
  lower to Rust array literals, indexing, and struct literals
- `Bitwise.bsr/2` and `Bitwise.band/2` lower to Rust `>>` and `&`
- aliases, remote calls, method calls, local calls, fields, tuples, nested tuple
  patterns, literals, lists as `vec![...]`, simple `for` comprehensions,
  expression/item macro calls, and one-argument `Enum.map/2` are supported
- Rust-facing attributes such as `@nif schedule: "DirtyCpu"` and
  `@allow :dead_code` are supported before `defrust`

Use semantic helpers such as `expr!`, `pat!`, `stmt!`, and `arm!` for
Rust-shaped values that are still authored as valid Elixir. `Super.*` calls mark
the boundary to nearby handwritten Rust primitives for Rustler term APIs,
generic `syn` parsing/assembly, or collection glue.

Ordinary Elixir `defmacro` and RustQ `defrustmacro` solve different problems.
Use `defmacro` when you want reusable Rusty-Elixir source; RustQ expands it
before lowering and the generated Rust does not contain a corresponding macro.
Use `defrustmacro` when repeated generated Rust should call one compact
`macro_rules!` helper while the helper body remains Rusty-Elixir:

```elixir
defrustmacro field(term, name, type: :ty) do
  decode_as!(required_field(term, name), type)
end

@spec decode(R.term()) :: R.nif_result(R.u32())
defrust decode(term) do
  field!(term, "value", R.u32())
end
```

Plain macro arguments are Rust `:expr` fragments. Annotate type arguments with
`:ty`, and use `:ident` / `:literal` for identifier and literal captures. The
body is not Rust token syntax: use ordinary calls, `decode_as!/2`, inference, and
other Rusty-Elixir forms. Keep `defrustmacro` small and supportive; do not hide
large functions inside macro bodies. In short: `defmacro` improves the Elixir
authoring layer; `defrustmacro` intentionally changes the Rust output shape.

`defrustmacro` can emit Rust items when its body contains an inner `defrust`:

```elixir
defrustmacro generated_decoder(
  fn: name(:ident),
  env: env(:ident),
  decoder: decoder(:ident),
  fields:
    repeat do
      field_id(:literal)
      field_name(:literal)
      field_decode(:ident)
    end
) do
  @spec name(R.path(:Env, R.lifetime(:a)), R.mut_ref(R.path(:Decoder))) ::
          R.nif_result(term())
  defrust name(env, decoder) do
    decode_fields(
      env,
      decoder,
      ref(
        array([
          repeat fields do
            struct_literal(Field, id: field_id, name: field_name, decode: field_decode)
          end
        ])
      )
    )
  end
end
```

In this context, declared captures lower to Rust macro variables and
`repeat fields do ... end` lowers to macro-template repetition, not a runtime
loop.

Raw token escapes (`raw_expr!`, `raw_pat!`, `raw_stmt!`, `raw_arm!`) are explicit
low-level escape hatches for cases not yet covered by semantic helpers. If an
escape grows beyond a small local syntax boundary, stop and add a RustQ semantic
helper or AST node instead.

RustQ dogfoods this layer in `RustQ.Codegen.Decoders.*` to generate much of
its own native AST decoder support.

For RustQ-owned helper modules that expose `defrust` functions for codegen,
`RustQ.Meta.item(module, name)`, `items(module, names)`, and `ast!(module, name)`
provide the internal bridge from a compiled `defrust` function to a reusable Rust
fragment or AST node:

```elixir
RustQ.Meta.item(MyApp.Native.Generated, :save)
RustQ.Meta.items(MyApp.Native.Generated, [:save, :restore])
RustQ.Meta.ast!(MyApp.Native.Generated, :save)
```

These helpers are intentionally small; they are for reusing RustQ-generated Rust
items without adding a binding-level framework.

### Callable metadata for propagation inference

RustQ can infer Rust `?` propagation when it knows the signature of the function
or method being called. Local `defrust` functions contribute callable metadata
from their `@spec`; external Rust callables can be imported at the `use RustQ.Meta`
boundary:

```elixir
defmodule MyApp.Native.GeneratedStyleHelpers do
  use RustQ.Meta,
    rust_sources: ["native/my_nif/src/style_helpers.rs"],
    rust_packages: [{"skia-safe", manifest_path: "native/my_nif/Cargo.toml"}],
    callable_modules: [MyApp.Native.GeneratedEnums]
end
```

Supported options are:

- `:rust_sources` — a Rust source path or list of paths. Relative paths are
  expanded from the current project working directory. RustQ parses free
  functions and `impl` methods from these files and refreshes cached metadata
  when the source file mtime or size changes.
- `:rust_packages` — a Cargo package name or `{package_name, opts}` entry, or a
  list of those entries. Options are passed to Cargo metadata lookup, commonly
  `manifest_path: "native/my_nif/Cargo.toml"`. RustQ indexes package Rust source
  structurally through `RustQ.Syn.Index.cached_package/2` and serializes initial
  cache population so parallel Elixir compilation does not stampede Cargo's
  package cache.
- `:callable_modules` — a RustQ module or list of modules that expose
  `__rustq_callables__/0`, usually another module using `RustQ.Meta`.

These options are validated with structured `RustQ.Diagnostic` errors. Prefer
small `rust_sources` or callable modules for project-owned helpers; use
`rust_packages` when the source of truth is an external crate and RustQ needs to
learn method signatures or public alias relationships from that crate.

With callable metadata, RustQ can propagate `?` through common Rust adapter
shapes without explicit `unwrap!` in Rusty Elixir, including local/remote/path
and method call arguments, downstream local bindings, receiver-method uses,
`ref(...)`, `as_ref()`, `as_slice()`, tuple elements, `Vec<T>.push(...)`,
`impl Into<T>`, `impl Into<Option<T>>`, `From<A> for B` evidence for
`impl Into<B>`, and `impl IntoIterator<Item = T>` vector arguments.

### Advanced: RustQ-owned modules with `defrustmod`

`defrustmod` is for RustQ-owned Rust module structure. Use the block form when
RustQ itself is responsible for generating the Rust module and the functions
inside it:

```elixir
defmodule MyApp.Native.Generated do
  use RustQ.Meta
  alias RustQ.Type, as: R

  defmodule Canvas do
    @type t :: term()
  end

  defrustmod GeneratedHelpers, as: :generated_helpers do
    @spec save(R.ref(Canvas.t())) :: R.nif_result(R.unit())
    defrust save(canvas) do
      canvas.save()
      :ok
    end
  end
end
```

This renders a Rust module such as:

```rust
mod generated_helpers {
    fn save(canvas: &Canvas) -> NifResult<()> {
        canvas.save();
        Ok(())
    }
}
```

Do not use `defrustmod` as a hand-written declaration for Rust modules that are
defined elsewhere by another generator or crate. If a downstream project already
generates or owns Rust like `mod generated_opts;`, express the type in the
`@spec` as an ordinary external remote type such as
`GeneratedOpts.OvalOpts.t(R.lifetime(:a))` and write body calls normally.

## Rust source introspection with `RustQ.Syn`

`RustQ.Syn` parses real Rust source with `syn` and returns Elixir metadata for
Rust items. It is for introspecting existing Rust crates, not for parsing Rust
with regex and not for producing Rusty-Elixir AST.

```elixir
file = RustQ.Syn.parse_file!("native/foo/src/lib.rs")

[file_enum | _] = RustQ.Syn.enums(file)
methods = RustQ.Syn.methods(file)

index = RustQ.Syn.Index.from_paths(Path.wildcard("native/foo/src/**/*.rs"))
method = RustQ.Syn.Index.method!(index, "Canvas", "draw_rect")
```

Metadata includes docs and structured type information while keeping rendered
Rust type strings for display/debugging:

```elixir
%RustQ.Syn.Method{
  name: "draw_rect",
  docs: ["Draws [`Rect`] rect using ..."],
  args: [
    %RustQ.Syn.Arg{
      name: "paint",
      type: "& Paint",
      type_ast: %RustQ.Syn.Type.Ref{
        inner: %RustQ.Syn.Type.Path{name: "Paint"}
      }
    }
  ]
}
```

Supported metadata currently covers top-level enums, structs, free functions,
`impl` blocks, methods, doc comments, and common Rust type shapes such as paths,
refs, tuples, `Option`, `Result`, `impl Trait`, slices, arrays, `Self`, and raw
fallbacks. `RustQ.Syn.Type` also provides small predicate helpers such as
`path?/2`, `ref_to?/2`, and `impl_trait?/3` for semantic matching.

## Generated files with `rustq.exs`

Create `rustq.exs` in your project root to keep generated files checked in and
fresh:

```elixir
use RustQ.Config

alias RustQ.Rustler

require_file "lib/my_app/codegen/content_schema.ex"

rust "native/my_nif/src/generated_term_helpers.rs" do
  Rustler.term_helpers(type_key: "atoms::r#type()")
end

rust "native/my_nif/src/generated_content.rs" do
  MyApp.Codegen.ContentSchema.rust_items()
end
```

The manifest is ordinary Elixir, so use aliases, helper functions, modules, and
macros to keep project-specific codegen readable.

Then run:

```sh
mix rustq.gen
mix rustq.gen --check
mix rustq.gen term_helpers
```

Path-only targets infer their name from the file name and strip a leading
`generated_`, so `generated_term_helpers.rs` is selectable as `term_helpers`.

Use `mix rustq.gen --check` in CI to fail when generated files are stale.

## Generate from real Rust templates

Templates are ordinary Rust with parseable placeholder forms:

```elixir
use RustQ.Sigil
alias RustQ.Rust

template = ~R"""
pub struct __rq_Resource {
    __rq_fields: (),
}

impl __rq_Resource {
    __rq_methods!();

    pub fn table() -> &'static str {
        __rq_table_name!()
    }
}
"""

code =
  template
  |> RustQ.parse!("resource.rs")
  |> RustQ.bind(Resource: :User, table_name: {:literal, "users"})
  |> RustQ.splice(:fields, [
    Rust.field(:id, :i64, vis: :pub),
    Rust.field(:name, :String, vis: :pub)
  ])
  |> RustQ.splice(:methods, [
    Rust.fn(:new,
      vis: :pub,
      args: [id: :i64, name: :String],
      returns: :Self,
      body: "Self { id, name }"
    )
  ])
  |> RustQ.codegen!()
```

For file templates:

```elixir
RustQ.render_file!("priv/templates/resource.rs",
  bind: [Resource: :User],
  splice: [fields: [RustQ.Rust.field(:id, :i64, vis: :pub)]]
)
```

Large templates can be split into Rust partials. Includes are expanded before
Rust parsing and are resolved relative to the including file:

```rust
// priv/templates/resource.rs
pub struct __rq_Resource {
    __rq_include!("resource/fields.rs");
}

impl __rq_Resource {
    __rq_include!("resource/methods.rs");
}
```

For string templates, pass `include_dir: "priv/templates"` to enable include
expansion. Include errors return structured metadata, including
`:include_stack`, so callers can present their own diagnostics.

## Placeholder forms

RustQ placeholders use the visually distinct `__rq_` prefix. The exact shape
matches the Rust syntax position, but the name is consistent with the Elixir
`bind:` or `splice:` key:

- `__rq_Name` — identifier, type path, or lifetime replacement
- `__rq_value!()` — expression or type replacement
- `__rq_items!();` — item splice point
- `__rq_methods!();` — impl-item splice point
- `__rq_body!();` — statement splice point
- `__rq_arms => unreachable!(),` — match-arm splice point
- `__rq_fields: (),` — struct-field splice point
- `__rq_include!("relative/path.rs");` — file include expanded before parsing
- `fn target(__rq_args: ()) {}` — function-argument splice point

Placeholders are replaced in parsed Rust syntax positions, not inside arbitrary
macro token trees. If you need a generated value in a macro call, bind it outside
the macro first:

```rust
let value = __rq_value!();
println!("{}", value);
```

instead of:

```rust
println!("{}", __rq_value!());
```

## Rust builders

`RustQ.Rust` provides small Elixir builders for common Rust fragments. Use these
when generating Rust declarations from data. For larger implementation bodies,
prefer `defrust` when the body can be valid Elixir, or real Rust templates when
handwritten Rust is clearer.

```elixir
alias RustQ.Rust

items = [
  Rust.use([:std, :sync, :OnceLock]),
  Rust.const(:TABLE, {:ref, :str}, Rust.expr(Rust.literal("users")), vis: :pub),
  Rust.struct(:User,
    vis: :pub,
    derive: [:Clone, :Debug],
    fields: [Rust.field(:id, :i64, vis: :pub)]
  )
]
```

Use `Rust.raw/1`, `Rust.item/1`, `Rust.impl_item/1`, `Rust.stmt/1`,
`Rust.expr/1`, and `Rust.arm/1` when hand-written Rust is clearer than a
builder.

When codegen already has a `RustQ.Rust.AST` item, use `Rust.ast_item/1` or
`Rust.ast_items/1` as the standard AST-to-fragment bridge instead of rendering
AST items by hand:

```elixir
alias RustQ.Rust
alias RustQ.Rust.AST.Builder, as: A

Rust.ast_item(A.const(:ANSWER, :i32, A.lit(42)))
```

For structural Rust item generation, prefer the AST builders directly. They
cover Rustler-friendly shapes such as lifetime-bearing impl blocks and receiver
arguments:

```elixir
A.impl(A.type_path(:Content),
  lifetimes: [:a],
  trait: A.type_path([:rustler, :Decoder], lifetimes: [:a]),
  items: [decode_function]
)

%RustQ.Rust.AST.Function{
  name: :encode,
  lifetime: :a,
  args: [A.receiver(), A.arg(:env, A.type_path([:rustler, :Env], lifetimes: [:a]))],
  returns: A.type_path([:rustler, :Term], lifetimes: [:a]),
  body: [A.return(A.method(:value, :encode, [:env]))]
}
```

## Rustler helpers

`RustQ.Rustler` generates common Rustler code as Rust fragments:

```elixir
RustQ.Rustler.atoms([:ok, :error, {"r#type", "type"}])
RustQ.Rustler.cached_atoms([:ok, node_changes: "nodeChanges"])

RustQ.Rustler.nif(:add,
  args: [a: :i64, b: :i64],
  returns: :i64,
  body: "a + b"
)

RustQ.Rustler.nif_exports(
  render_png: [
    args: [env: "Env<'a>", batch: "Term<'a>"],
    returns: "NifResult<Term<'a>>",
    lifetime: :a,
    schedule: :dirty_cpu
  ]
)

RustQ.Rustler.term_helpers(type_key: "atoms::r#type()")
RustQ.Rustler.opts_helpers()
RustQ.Rustler.term_decoder(:ProgramInput,
  fields: [
    body: [type: {:vec, "Term<'a>"}, key: "atoms::body()", required: true]
  ]
)

RustQ.Rustler.resource_handle(:EncodedImage,
  fields: [bytes: "Vec<u8>"],
  handle_field: "ref"
)
```

Atom-based decoders and dispatchers are intentionally low-level so projects can
compose them into their own command, AST, or schema models:

```elixir
RustQ.Rustler.atom_decoder(:decode_blend_mode,
  returns: :BlendMode,
  cases: [src_over: "BlendMode::SrcOver", multiply: "BlendMode::Multiply"]
)

RustQ.Rustler.atom_dispatch(:draw_command,
  args: [surface: "&mut Surface", command: "Term<'a>"],
  on: "command.map_get(atoms::op())?.decode::<Atom>()?",
  cases: [rect: "draw_rect(surface, command)"],
  unknown: "Ok(())"
)
```

Safe term builders use `Term<'a>`:

```elixir
RustQ.Rustler.term_builders(include: [:map_from_terms, :struct_from_terms])
```

Low-level raw `NIF_TERM` helpers are explicit:

```elixir
RustQ.Rustler.nif_term_builders(include: [:map_from_nif_terms, :struct_from_nif_terms])
```

## Rustler schema DSL

For larger Elixir struct surfaces, define a schema once and generate Rust NIF
structs plus tagged enums:

```elixir
defmodule MyApp.Codegen.ContentSchema do
  use RustQ.Rustler.Schema

  schema MyApp.Content do
    default_attrs ["allow(dead_code)"]

    node Text do
      field :text, :String
      field :size, {:option, :String}
    end

    node Paragraph do
      field :body, {:vec, Content}
    end

    node Enum, rust: :ExEnum, module: MyApp.Content.EnumList do
      field :children, {:vec, Content}
    end

    tagged_enum Content do
      variants :all
      unknown :unknown_content_variant
    end
  end
end
```

Optionality is part of the Rust type (`{:option, :String}`), not a separate
boolean flag.

## Composing splices

When multiple generators contribute to one template, pass nested splice sources
or use `RustQ.Splice.merge/1`. Duplicate names are concatenated:

```elixir
RustQ.render_file!("native/src/generated.template.rs",
  splice: [
    MyApp.BaseGenerator.splices(schema),
    MyApp.NativeGenerator.splices(schema),
    items: RustQ.Rust.item("pub fn generated() {}")
  ]
)
```

For explicit composition:

```elixir
splices =
  RustQ.Splice.merge([
    MyApp.BaseGenerator.splices(schema),
    MyApp.NativeGenerator.splices(schema),
    items: RustQ.Rust.item("pub fn generated() {}")
  ])
```

## Optional rustfmt

Pass `rustfmt: true` to format generated source through `rustfmt --emit stdout`:

```elixir
RustQ.render_file!("native/src/generated.template.rs",
  splice: [items: items],
  rustfmt: true
)
```

You can also pass a command path/string with `rustfmt: "/path/to/rustfmt"`.
Rustfmt failures return structured `:rustfmt_error` metadata.

## Fragment validation and native AST rendering

You can validate individual Rust fragments in the same contexts RustQ splices:

```elixir
RustQ.valid_fragment?(:field, "pub id: i64")
RustQ.parse_fragment!(:arm, RustQ.Rust.arm("Some(value)", "value"))
```

Native AST rendering is the required backend for RustQ AST items. Unsupported
nodes fail visibly instead of falling back to a parallel Elixir renderer, so new
AST nodes must include native decoding/rendering coverage.

## License

MIT
