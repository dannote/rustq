# RustQ Reach plugin

RustQ ships optional Reach checks that reinforce the authoring practices in
[Using RustQ Well](using-rustq-well.md). They catch architectural drift such as
large raw Rust escapes, missing specs, low-level control flow in product
Rusty-Elixir, and wrappers that only hide missing metadata.

These checks are guardrails, not syntax requirements and not a replacement for
behavioral tests or compiling generated Rust.

## Enable the checks

Add Reach to the consumer project's development dependencies and choose the
checks appropriate for that project in `.reach.exs`:

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

Run the project's normal Reach gate, commonly:

```bash
mix reach.check --arch --smells
```

## Project ownership

Consumers own strictness, ignored paths, and baselines. RustQ's portable checks
do not contain project-specific exemptions.

Review a finding semantically before suppressing it. A low-level parser,
`macro_rules!` invocation, unsafe Rustler primitive, or external adapter may be a
legitimate boundary. Keep such exceptions local and document why the higher
RustQ layer does not fit.

Do not turn an architectural rule into an ExUnit test that greps source files.
Use Reach or another architecture tool for policy; use tests for behavior and
generated output.
