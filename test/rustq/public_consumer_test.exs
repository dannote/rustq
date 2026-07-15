defmodule RustQ.PublicConsumerTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 600_000

  @root Path.expand("../..", __DIR__)
  @fixture Path.join(@root, "integration/public_consumer")

  test "the packaged artifact supports a clean external consumer" do
    workspace =
      Path.join(System.tmp_dir!(), "rustq-public-consumer-#{System.unique_integer([:positive])}")

    package = Path.join(workspace, "rustq-package")
    consumer = Path.join(workspace, "consumer")

    File.rm_rf!(workspace)
    File.mkdir_p!(workspace)

    on_exit(fn -> File.rm_rf!(workspace) end)

    run!(@root, "mix", ["hex.build", "--unpack", "--output", package])
    assert File.regular?(Path.join(package, "SKILL.md"))
    assert File.regular?(Path.join(package, "guides/compatibility.md"))

    File.cp_r!(@fixture, consumer)

    env = [{"RUSTQ_PACKAGE_PATH", package}, {"MIX_ENV", "test"}]

    run!(consumer, "mix", ["deps.get"], env)
    run!(consumer, "mix", ["rustq.gen", "--check"], env)
    run!(consumer, "mix", ["test"], env)
    run!(consumer, "cargo", ["check", "--manifest-path", "native/Cargo.toml"], env)

    generated = File.read!(Path.join(consumer, "native/src/generated.rs"))
    assert generated =~ "fn increment_all"
    assert generated =~ "struct Input"
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
