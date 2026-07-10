# RustQ Reach plugin

RustQ ships its Reach plugin with the `rustq` package. No separate RustQ plugin
package is required.

Add Reach to the consumer project's development dependencies, then enable the
checks the project wants in `.reach.exs`:

```elixir
[
  smells: [
    strict: true,
    custom_checks: [
      RustQ.Reach.Smells.RawRustEscape,
      RustQ.Reach.Smells.DynamicRawRustEscape,
      RustQ.Reach.Smells.DefrustMissingSpec,
      RustQ.Reach.Smells.LowLevelControlFlow,
      RustQ.Reach.Smells.TrivialDefrustWrapper,
      RustQ.Reach.Smells.BlocklessDefrustmod
    ]
  ]
]
```

Consumers own their Reach strictness, ignore paths, and baselines; RustQ's
checks contain no consumer-specific path or function exemptions.
