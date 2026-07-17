# RustQ public consumer fixture

This is a deliberately separate Mix and Cargo project that exercises RustQ only
through documented public APIs.

`RustQ.PublicConsumerTest` builds and unpacks the current Hex package artifact,
copies this project to a temporary workspace, points `RUSTQ_PACKAGE_PATH` at the
unpacked package, and verifies:

- dependency compilation from packaged files
- checked `rustq.exs` generation
- documented Elixir APIs, composable `RustQ.Test` helpers, and generated `RustQ.Meta`
  accessors
- structural Rust AST and Rustler helpers
- native Cargo compilation

The fixture must not call hidden renderer, native NIF, lowering, inference,
cache, or schema-introspection modules. Keep it small enough to identify public
API drift without duplicating RustQ's unit suite.

For direct local use:

```sh
RUSTQ_PACKAGE_PATH=/absolute/path/to/unpacked/rustq mix deps.get
RUSTQ_PACKAGE_PATH=/absolute/path/to/unpacked/rustq mix rustq.gen --check
RUSTQ_PACKAGE_PATH=/absolute/path/to/unpacked/rustq MIX_ENV=test mix test
cargo check --manifest-path native/Cargo.toml
```
