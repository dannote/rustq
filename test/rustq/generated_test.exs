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

  test "loads generated content declared with RustQ.Config" do
    path = tmp_path("rustq.exs")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    use RustQ.Config

    generate :helpers, "native/generated.rs" do
      content "fn main() {}\\n"
    end
    """)

    assert [helpers: target] = Generated.load_manifest!(path)
    assert Keyword.fetch!(target, :path) == "native/generated.rs"
    assert Keyword.fetch!(target, :content) == "fn main() {}\n"
  end

  test "loads structural Rust targets" do
    path = tmp_path("rustq.exs")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    use RustQ.Config
    alias RustQ.Rust.AST.Builder, as: A

    rust "native/generated_helpers.rs" do
      A.const(:FIRST, :u32, A.lit(1))
      [A.const(:SECOND, :u32, A.lit(2))]
    end
    """)

    assert [{"helpers", target}] = Generated.load_manifest!(path)
    code = Keyword.fetch!(target, :build).()
    assert code =~ "const FIRST: u32 = 1;"
    assert code =~ "const SECOND: u32 = 2;"
  end

  test "loads structural items from a defrust module" do
    path = tmp_path("rustq.exs")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    use RustQ.Config

    defmodule GeneratedDefrustManifest do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec generated(R.ref(Canvas.t())) :: R.nif_result(R.unit())
      defrust generated(canvas) do
        canvas.save()
        :ok
      end
    end

    rust "native/generated_helpers.rs" do
      GeneratedDefrustManifest.__rustq_items__()
    end
    """)

    assert [{"helpers", target}] = Generated.load_manifest!(path)
    code = Keyword.fetch!(target, :build).()
    assert code =~ "fn generated(canvas: &Canvas) -> NifResult<()>"
    assert code =~ "canvas.save();"
  end

  test "loads ordinary manifest values" do
    path = tmp_path("rustq.exs")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    [generated: [helpers: [path: "native/generated.rs", content: "fn main() {}\\n"]]]
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
