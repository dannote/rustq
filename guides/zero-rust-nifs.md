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
checked-in `.rs` file. Generated crates are formatted before compilation and
are available under the Mix build directory for inspection. The existing
manifest and structural generator APIs remain available for advanced
multi-target generators and existing crates.

Boundary derivation covers scalar values, strings, binaries, tuples, lists,
options, tagged results, typed maps, Elixir structs and exceptions, structural
unions, unit enums, and explicitly declared resources. A generated resource can
be declared without bridge Rust by wrapping a structural state type:

```elixir
@type counter_state :: %{required(:value) => integer()}
@type counter :: R.resource(counter_state())

@spec new_counter(integer()) :: counter()
defnif new_counter(value), do: %{value: value}

@spec counter_value(counter()) :: integer()
defnif counter_value(counter), do: counter.value
```

Resource mutation, synchronization, and thread-safety remain explicit policy;
`R.resource/1` only derives registration and the `ResourceArc` boundary.

Function-head guards and `case` `when` guards lower through the same typed
expression path as ordinary Rusty-Elixir conditions. Comparisons, boolean
operators, arithmetic guard expressions, and supported typed calls therefore
work for both `defrust` and `defnif`; unsupported semantics produce a lowering
diagnostic rather than being dropped.

Consumer tests can use the packaged ExUnit helpers:

```elixir
use RustQ.Test, async: true

assert_defrust MyApp.Native, :sum_impl, "fn sum_impl"
assert_defnif MyApp.Native, :sum, 1, ~r/fn sum.*Vec<f64>/
assert_rust_valid MyApp.Native
```

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

Standard-library calls are normalized and dispatched through hidden, focused
Kernel, Enum, List, Map, String, Tuple, and Range lowerers. The 1.0 subset
currently includes:

- Kernel arithmetic, comparisons, booleans, `div`, `rem`, `abs`, integer
  `min`/`max`, `byte_size`, tuple access/update/size, ascending literal ranges,
  and membership
- Enum mapping, filtering, rejecting, flat-mapping, reducing, summing,
  counting, predicates, membership, finding, concatenation, zip/unzip,
  integer sorting, reversal, and non-negative take/drop
- List first/last (with optional defaults), static wrapping/duplication, and
  statically nested flattening
- typed map/struct lookup, presence checks, and field replacement
- String prefix, suffix, substring, trim, replacement, duplication, and UTF-8
  validity operations
- homogeneous `Tuple.to_list/1`

These lowerers own their call-specific type synthesis as well as Rust AST
emission. RustQ rejects or leaves explicit any call whose Elixir semantics
cannot be preserved. In particular, descending/dynamic ranges, negative dynamic
Enum take/drop counts, heterogeneous tuple-to-list conversion, dynamic maps,
and grapheme-counting `String.length/1` do not silently become similar-looking
Rust operations.

RustQ does not promise full BEAM semantics in generated Rust. Process
mailboxes, supervision, dynamic code loading, unrestricted exceptions, every
protocol or standard-library function, async Rust, and the complete bitstring
grammar are not 1.0 requirements. `Stream`, `Regex`, `URI`, calendar, filesystem,
IO, networking, and process APIs remain explicit Rust or adapter boundaries.

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
