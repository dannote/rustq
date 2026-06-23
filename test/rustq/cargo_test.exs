defmodule RustQ.CargoTest do
  use ExUnit.Case, async: true

  @manifest_path "native/rustq_nif/Cargo.toml"

  test "decodes cargo metadata into structs" do
    assert %RustQ.Cargo.Metadata{packages: packages} =
             RustQ.Cargo.metadata!(manifest_path: @manifest_path)

    assert Enum.any?(packages, &match?(%RustQ.Cargo.Package{name: "rustq_nif"}, &1))
  end

  test "caches cargo metadata and refreshes when the manifest changes" do
    dir =
      Path.join(System.tmp_dir!(), "rustq_cargo_metadata_#{System.unique_integer([:positive])}")

    manifest_path = Path.join(dir, "Cargo.toml")
    File.mkdir_p!(Path.join(dir, "src"))

    on_exit(fn ->
      RustQ.Cargo.clear_cached_metadata(manifest_path: manifest_path)
      File.rm_rf(dir)
    end)

    File.write!(Path.join([dir, "src", "lib.rs"]), "pub fn one() {}\n")

    File.write!(manifest_path, """
    [package]
    name = "rustq_metadata_one"
    version = "0.1.0"
    edition = "2021"
    """)

    assert %RustQ.Cargo.Metadata{packages: packages} =
             RustQ.Cargo.metadata!(manifest_path: manifest_path)

    assert Enum.any?(packages, &match?(%RustQ.Cargo.Package{name: "rustq_metadata_one"}, &1))

    File.write!(manifest_path, """
    [package]
    name = "rustq_metadata_two"
    version = "0.1.0"
    edition = "2021"
    """)

    assert %RustQ.Cargo.Metadata{packages: packages} =
             RustQ.Cargo.metadata!(manifest_path: manifest_path)

    assert Enum.any?(packages, &match?(%RustQ.Cargo.Package{name: "rustq_metadata_two"}, &1))
  end

  test "finds package source roots without assuming registry layout" do
    assert RustQ.Cargo.package_source!("rustq_nif", manifest_path: @manifest_path) ==
             Path.expand("native/rustq_nif")
  end

  test "builds source links for registry packages" do
    package = %RustQ.Cargo.Package{
      name: "skia-safe",
      version: "0.88.0",
      source: "registry+https://github.com/rust-lang/crates.io-index",
      manifest_path: "/cargo/registry/skia-safe-0.88.0/Cargo.toml"
    }

    assert RustQ.Cargo.source_link(
             package,
             "/cargo/registry/skia-safe-0.88.0/src/core/canvas.rs",
             1351
           ) == "https://docs.rs/crate/skia-safe/0.88.0/source/src/core/canvas.rs#L1351"
  end
end
