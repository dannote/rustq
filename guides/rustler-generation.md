# Generating Rustler Boundaries

RustQ can generate repetitive Rustler boundary code while keeping implementation
logic in ordinary Rust. Use structural manifests and Rust source metadata rather
than duplicating signatures across Rust and Elixir.

## Atom registries

Discover atom calls structurally with `RustQ.Syn.atom_references!/1`, then emit
the registry with `RustQ.Rustler.atoms/2`. The scanner recognizes calls in
ordinary expressions and Rust macro token trees.

```elixir
atoms =
  "native/my_nif/src/*.rs"
  |> Path.wildcard()
  |> Enum.flat_map(fn path -> path |> File.read!() |> RustQ.Syn.atom_references!() end)
  |> Enum.uniq()
  |> Enum.sort()

rust "native/my_nif/src/generated_atoms.rs" do
  RustQ.Rustler.atoms(atoms)
end
```

Exclude generated files from discovery. If another manifest introduces atom
keys, derive those keys directly from that manifest so generation reaches a
stable result in one pass.

## Struct term encoders

`term_encoder/2` generates a `rustler::Encoder` implementation backed by RustQ
AST. Simple fields are atoms; `{key, field}` renames the atom key.

```elixir
RustQ.Rustler.term_encoder(:EncodedLocation,
  fields: [:start, {:end_, :end}, :line]
)
```

Lifetime-bearing adapters use `:target_lifetimes`:

```elixir
RustQ.Rustler.term_encoder(:EncodedError,
  target_lifetimes: [:_],
  fields: [:message, code: [when_some: true, via: :as_str]]
)
```

Field metadata supports structural transformations:

- `field: [:result, :code]` — nested field path
- `via: :as_str` — zero-argument method before encoding
- `with: :encode_value` — helper called as `encode_value(env, &value)`
- `borrow: false` — pass the helper value without adding `&`
- `when_some: true` — omit the map entry when the option is `None`
- `optional: [wrap: :EncodedValue]` — encode `Some` through an adapter and `None` as nil
- `map: [wrap: :EncodedValue]` — map a collection into encoded terms
- `map: [convert: :EncodedValue]` — map through `EncodedValue::from`
- `fallback: [field: [:result, :code], via: :as_str]` — generate `unwrap_or`

These are typed operations, not raw Rust expression strings.

## One NIF manifest for Rust and Elixir

Keep NIF bodies as handwritten implementation functions with an `_impl` suffix:

```rust
fn parse_nif_impl<'a>(env: Env<'a>, source: &str) -> NifResult<Term<'a>> {
    // domain implementation
}
```

Declare boundary policy once:

```elixir
nifs = [
  parse_nif: [],
  compile_nif: [attrs: [A.attr(:allow, [A.path([:clippy, :too_many_arguments])])]]
]

rust "native/my_nif/src/generated_nif_exports.rs" do
  RustQ.Rustler.nif_exports_from_source(
    "native/my_nif/src/lib.rs",
    nifs,
    lifetime: :a,
    schedule: :dirty_cpu
  )
end

generate "lib/my_app/generated_nif_stubs.ex" do
  content(
    RustQ.Rustler.nif_stubs_from_source(
      "native/my_nif/src/lib.rs",
      nifs,
      MyApp.GeneratedNifStubs
    )
  )
end
```

The Rust wrapper signatures come from `RustQ.Syn`; they are not repeated in the
manifest. Elixir stub arities use the same signatures and structurally exclude
Rustler's injected `Env` argument.

Retain human-facing specs in the native module and install generated stubs once:

```elixir
defmodule MyApp.Native do
  @spec parse_nif(String.t()) :: {:ok, map()} | {:error, term()}

  use MyApp.GeneratedNifStubs
end
```

Run both generation and compiler checks in CI:

```elixir
lint: [
  "rustq.gen --check",
  "compile --warnings-as-errors"
]
```
