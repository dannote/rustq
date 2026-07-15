defmodule RustQ.PublicConsumerTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 600_000

  @root Path.expand("../..", __DIR__)
  @fixture Path.join(@root, "integration/public_consumer")
  @zero_rust_fixture Path.join(@root, "integration/zero_rust_consumer")

  test "the packaged artifact supports a clean external consumer" do
    workspace =
      Path.join(System.tmp_dir!(), "rustq-public-consumer-#{System.unique_integer([:positive])}")

    package = Path.join(workspace, "rustq-package")
    consumer = Path.join(workspace, "consumer")
    zero_rust_consumer = Path.join(workspace, "zero-rust-consumer")

    File.rm_rf!(workspace)
    File.mkdir_p!(workspace)

    on_exit(fn -> File.rm_rf!(workspace) end)

    run!(@root, "mix", ["hex.build", "--unpack", "--output", package])
    assert File.regular?(Path.join(package, "SKILL.md"))
    assert File.regular?(Path.join(package, "guides/compatibility.md"))
    assert File.regular?(Path.join(package, "guides/zero-rust-nifs.md"))

    File.cp_r!(@fixture, consumer)

    env = [{"RUSTQ_PACKAGE_PATH", package}, {"MIX_ENV", "test"}]

    run!(consumer, "mix", ["deps.get"], env)
    run!(consumer, "mix", ["rustq.gen", "--check"], env)
    run!(consumer, "mix", ["test"], env)
    run!(consumer, "cargo", ["check", "--manifest-path", "native/Cargo.toml"], env)

    generated = File.read!(Path.join(consumer, "native/src/generated.rs"))
    assert generated =~ "fn increment_all"
    assert generated =~ "struct Input"

    assert Path.wildcard(Path.join(@zero_rust_fixture, "**/*.rs")) == []
    refute File.exists?(Path.join(@zero_rust_fixture, "Cargo.toml"))
    refute File.exists?(Path.join(@zero_rust_fixture, "rustq.exs"))

    File.cp_r!(@zero_rust_fixture, zero_rust_consumer)
    run!(zero_rust_consumer, "mix", ["deps.get"], env)
    run!(zero_rust_consumer, "mix", ["test"], env)

    [native_source] =
      Path.wildcard(Path.join(zero_rust_consumer, "_build/test/rustq_native/*/src/lib.rs"))

    source = File.read!(native_source)
    assert source =~ "#[rustler::nif]"
    assert source =~ "fn add(left: i64, right: i64) -> i64"
    assert source =~ ~s|rustler::init! { "Elixir.RustQZeroRustConsumer.Native" }|
  end

  defp run!(directory, command, args, env \\ []) do
    {output, status} =
      System.cmd(command, args,
        cd: directory,
        env: env,
        stderr_to_stdout: true
      )

    assert status == 0,
           "#{command} #{Enum.join(args, " ")} failed in #{directory}:\n#{output}"

    output
  end
end
