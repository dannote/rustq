# Zero-handwritten-Rust NIFs

RustQ 1.0 targets a zero-handwritten-bridge-Rust workflow for ordinary NIFs.
The implementation and boundary are authored in Elixir; RustQ generates,
builds, and loads the Rust crate.

The intended starting point is:

```elixir
defmodule MyApp.Native do
  use RustQ.Native

  @spec sum([float()]) :: float()
  defnif sum(values) do
    Enum.sum(values)
  end
end
```

`defnif` declares a public BEAM↔Rust entrypoint. `defrust` remains the form for
generated Rust helpers, and `defrustp` declares private generated helpers.
Ordinary Elixir macros remain the preferred way to generate or reuse all three.

## What RustQ owns

For a zero-Rust native module, RustQ owns:

- the generated Cargo package and Rust source
- Rustler NIF attributes and initialization
- Elixir stubs and native-library loading
- directional argument and return codecs
- atom and structural type declarations
- incremental native compilation and generated-source inspection

The simple path does not require `rustq.exs`, a checked-in `Cargo.toml`, or a
checked-in `.rs` file. The existing manifest and structural generator APIs
remain available for advanced multi-target generators and existing crates.

## What remains explicit

Minimal configuration does not mean guessing about safety or deployment.
Consumers still own genuine policy such as:

- Cargo dependency versions, features, paths, and Git sources
- dirty CPU or dirty IO scheduling
- resource ownership, mutation, and thread-safety
- blocking operations, unsafe operations, and platform linking
- lossy conversions and custom external-type or error adapters
- precompiled artifact targets and release hosting

## 1.0 lowering target

The 1.0 Rusty-Elixir surface includes enough ordinary Elixir to implement and
compose a representative native bridge:

- multiple clauses, function-head patterns and guards, and recursion
- `case`, `if`, `unless`, `cond`, `with`, and comprehensions
- tuple, atom, option/result, list, map, and struct values and patterns
- common arithmetic, comparison, boolean, range, and membership operators
- common `Enum` mapping, filtering, reducing, searching, and predicate forms
- closures, named captures, pipelines, and ordinary Elixir macro expansion
- typespec-derived scalar, string, binary, list, tuple, map, struct, union,
  exception, and resource boundaries

RustQ does not promise full BEAM semantics in generated Rust. Process
mailboxes, supervision, dynamic code loading, unrestricted exceptions, every
protocol or standard-library function, async Rust, and the complete bitstring
grammar are not 1.0 requirements.

## Compiler boundary

RustQ treats Elixir types, internal Rust values, and NIF ABI values as related
but distinct representations. For example, an Elixir `binary()` may decode as
a borrowed Rustler binary, be used internally as a byte slice, and encode from
an owned byte vector.

The compilation pipeline is therefore semantic rather than textual:

```text
expanded Elixir AST and typespecs
  -> Rusty-Elixir core representation
  -> type, effect, ownership, and borrowing inference
  -> directional boundary codec derivation
  -> RustQ Rust AST
  -> generated crate, Cargo build, and NIF loading
```

Raw Rust remains an explicit escape hatch, not a prerequisite for starting a
binding.
