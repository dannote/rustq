# Zero-Rust public consumer

This packaged-artifact fixture proves RustQ can generate, compile, load, and
invoke a Rustler NIF from Elixir alone. The fixture intentionally contains no
`.rs` file, `Cargo.toml`, or `rustq.exs`; generated native sources live only
under the Mix build directory. Its grouped ExUnit tests use `RustQ.Test` for
focused `defnif` metadata assertions alongside runtime behavior checks.
