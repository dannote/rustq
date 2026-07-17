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
    ],
    ignore: [
      paths: [
        "test/support/**",
        "lib/rustq.ex",
        "lib/rustq/rust/ast/builder.ex",
        "lib/rustq/rustler/atom.ex",
        "lib/rustq/rustler/nif.ex",
        "lib/rustq/rustler/opts.ex",
        "lib/rustq/rustler/schema.ex",
        "lib/rustq/rustler/term.ex"
      ]
    ]
  ]
]
