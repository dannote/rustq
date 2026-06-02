defmodule RustQ.GeneratedTest do
  use ExUnit.Case, async: true

  alias RustQ.Generated

  test "writes generated targets" do
    path = tmp_path("generated.rs")

    assert :ok = Generated.sync!(:helpers, path: path, build: fn -> "fn main() {}\n" end)
    assert File.read!(path) == "fn main() {}\n"
  end

  test "checks fresh generated targets" do
    path = tmp_path("fresh.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "fn main() {}\n")

    assert :ok = Generated.sync!(:helpers, [path: path, content: "fn main() {}\n"], check: true)
  end

  test "raises on stale generated targets" do
    path = tmp_path("stale.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "old\n")

    assert_raise Generated.StaleError, ~r/Run: mix rustq.gen/, fn ->
      Generated.sync!(:helpers, [path: path, content: "new\n"], check: true)
    end
  end

  test "reports all stale generated targets" do
    first = tmp_path("first.rs")
    second = tmp_path("second.rs")
    File.mkdir_p!(Path.dirname(first))
    File.mkdir_p!(Path.dirname(second))
    File.write!(first, "old\n")
    File.write!(second, "old\n")

    assert_raise Generated.StaleError, ~r/first.rs.*second.rs/s, fn ->
      Generated.sync_all!(
        [
          first: [path: first, content: "new\n"],
          second: [path: second, content: "new\n"]
        ],
        check: true
      )
    end
  end

  test "supports custom stale commands" do
    path = tmp_path("stale-custom.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "old\n")

    assert_raise Generated.StaleError, ~r/Run: mix skia.codegen/, fn ->
      Generated.sync!(:helpers, [path: path, content: "new\n"],
        check: true,
        command: "mix skia.codegen"
      )
    end
  end

  test "runs configured checks during generated file checks" do
    path = tmp_path("generated.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "fn main() {}\n")

    assert :ok =
             Generated.sync_all!(
               [helpers: [path: path, content: "fn main() {}\n", check: "true"]],
               check: true
             )
  end

  test "loads rustq manifests with the optional wrapper DSL" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    import RustQ.Config

    rustq do
      generate :helpers, "native/generated.rs" do
        content "fn main() {}\\n"
      end
    end
    """)

    assert [helpers: target] = Generated.load_manifest!(path)
    assert Keyword.fetch!(target, :path) == "native/generated.rs"
    assert Keyword.fetch!(target, :content) == "fn main() {}\n"
  end

  test "loads rustq manifests with rust_items shortcut" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    import RustQ.Config

    rust_items :helpers, "native/generated.rs", items: [RustQ.Rust.fn(:main, body: "")]
    """)

    assert [helpers: target] = Generated.load_manifest!(path)
    assert Keyword.fetch!(target, :path) == "native/generated.rs"
    assert Keyword.fetch!(target, :build).() =~ "fn main()"
  end

  test "flattens nested rust_items lists" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    import RustQ.Config

    rust_items "native/generated_helpers.rs",
      items: [
        RustQ.Rust.fn(:first, body: ""),
        [RustQ.Rust.fn(:second, body: "")]
      ]
    """)

    assert [{"helpers", target}] = Generated.load_manifest!(path)
    code = Keyword.fetch!(target, :build).()
    assert code =~ "fn first()"
    assert code =~ "fn second()"
  end

  test "infers names for rust_items shortcut" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    import RustQ.Config

    rust_items "native/generated_helpers.rs", items: [RustQ.Rust.fn(:main, body: "")]
    """)

    assert [{"helpers", target}] = Generated.load_manifest!(path)
    assert Keyword.fetch!(target, :path) == "native/generated_helpers.rs"
  end

  test "loads rustq manifests with render shortcut" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    import RustQ.Config

    generate :helpers, "native/generated.rs" do
      render "fn main() {}"
    end
    """)

    assert [helpers: target] = Generated.load_manifest!(path)
    assert Keyword.fetch!(target, :path) == "native/generated.rs"
    assert Keyword.fetch!(target, :build).() =~ "fn main()"
  end

  test "loads rustq manifests with top-level generate calls" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    import RustQ.Config

    generate :helpers, "native/generated.rs" do
      content "fn main() {}\\n"
    end
    """)

    assert [helpers: target] = Generated.load_manifest!(path)
    assert Keyword.fetch!(target, :path) == "native/generated.rs"
    assert Keyword.fetch!(target, :content) == "fn main() {}\n"
  end

  test "loads rustq manifests" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    [
      generated: [
        helpers: [path: "native/generated.rs", content: "fn main() {}\\n"]
      ]
    ]
    """)

    assert [helpers: [path: "native/generated.rs", content: "fn main() {}\n"]] =
             Generated.load_manifest!(path)
  end

  defp tmp_path(name) do
    Path.join([
      System.tmp_dir!(),
      "rustq-generated-test",
      "#{System.unique_integer([:positive])}",
      name
    ])
  end
end
