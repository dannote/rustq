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
        "lib/rustq/rustler/opts.ex"
      ]
    ]
  ]
]
