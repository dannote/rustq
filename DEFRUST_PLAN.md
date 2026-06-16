# `defrust` macro frontend plan

`defrust` is a valid-Elixir macro frontend for RustQ. It uses ordinary Elixir
syntax and `@spec`/`@type` declarations as the authoring surface, then lowers the
quoted Elixir AST to existing `RustQ.Rust` fragments.

## Design principles

- The source language must be valid Elixir.
- No fake Rust syntax: no `let`, no `?`, no `Some(x)`, no Rust-style `->` outside
  normal Elixir constructs.
- Ordinary Elixir assignment (`=`) lowers to Rust `let`.
- Ordinary Elixir `case` lowers to Rust `match`.
- Ordinary remote calls (`Rect.from_xywh(...)`) lower to Rust path calls
  (`Rect::from_xywh(...)`).
- Ordinary variable method calls (`canvas.draw_rect(...)`) lower to Rust method
  calls (`canvas.draw_rect(...)`).
- `nil`, `:ok`, `{:ok, value}`, and `{:error, reason}` map to Rust
  `None`, `Ok(())`, `Ok(value)`, and `Err(reason)` when the expected type calls
  for it.
- Explicit valid-Elixir helpers such as `ref/1`, `mut_ref/1`, `unwrap!/1`,
  `some/1`, `none/0`, `ok/0`, `ok/1`, and `err/1` are allowed where inference is
  not enough.
- Generated Rust is still validated through RustQ's existing Rust parser and
  fragment validation.

## Target user shape

```elixir
defmodule Skia.Native.Generated do
  use RustQ.Meta
  alias RustQ.Type, as: R

  @spec draw_save(R.ref(Canvas.t())) :: R.nif_result(R.unit())
  defrust draw_save(canvas) do
    canvas.save()
    :ok
  end

  @spec decode_mode(R.atom()) :: R.nif_result(BlendMode.t())
  defrust decode_mode(atom) do
    case atom do
      :src_over -> {:ok, BlendMode.SrcOver}
      :multiply -> {:ok, BlendMode.Multiply}
      _ -> {:error, :invalid_blend_mode}
    end
  end
end
```

## Initial milestones

1. Add `RustQ.Type`, a typespec-only vocabulary for Rust primitive/container
   types.
2. Add `RustQ.Meta.defrust/2` and collect generated Rust items in a module
   attribute.
3. Parse the preceding `@spec` AST for function args and return type.
4. Lower to a small Elixir-side Rust AST/IR (`RustQ.Rust.AST`) before rendering
   at the final RustQ fragment-validation boundary.
5. Lower a small valid-Elixir subset:
   - `x = expr` -> `let x = expr;`
   - final `:ok` in `R.nif_result(R.unit())` -> `Ok(())`
   - `{:ok, value}` -> `Ok(value)`
   - `{:error, reason}` -> `Err(reason)`
   - `case` -> `match`
   - atoms, variables, tuples, numeric/string literals
   - aliases and remote calls
   - `ref/1`, `mut_ref/1`, `unwrap!/1`
6. Provide `__rustq_asts__/0`, `__rustq_items__/0`, and `__rustq_source__/0` on
   modules using `RustQ.Meta`.
7. Add `from_module My.Generated` for `rustq.exs`/`mix rustq.gen` integration.
8. Add native `render_ast/1` backend that decodes `RustQ.Rust.AST.Function` into
   `syn` and renders with `prettyplease`.
9. Add tests proving generated fragments for `draw_save`, `decode_mode`, and a
   small assignment/body example.

## Later work

- Expand native NIF AST backend coverage beyond the MVP function/statement/expression nodes.
- Full set-theoretic `@type` parsing for atom unions, tuples, maps, options,
  results, and Rustler decoder generation.
- Better type-directed wrapping for `Option`, `Result`, and `NifResult` in nested
  `case` branches.
- Broader integration with `mix rustq.gen` so `defrust` modules can directly emit
  schemas and multi-file output.
