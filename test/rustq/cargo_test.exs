defmodule RustQ.CargoTest do
  use ExUnit.Case, async: true

  @manifest_path "native/rustq_nif/Cargo.toml"

  test "decodes cargo metadata into structs" do
    assert %RustQ.Cargo.Metadata{packages: packages} =
             RustQ.Cargo.metadata!(manifest_path: @manifest_path)

    assert Enum.any?(packages, &match?(%RustQ.Cargo.Package{name: "rustq_nif"}, &1))
  end

  test "finds package source roots without assuming registry layout" do
    assert RustQ.Cargo.package_source!("rustq_nif", manifest_path: @manifest_path) ==
             Path.expand("native/rustq_nif")
  end
end
