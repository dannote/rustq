defmodule RustQ.Test.PackageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import RustQ.Test.PackageCase
    end
  end

  def build_package_workspace!(root) do
    workspace =
      Path.join(System.tmp_dir!(), "rustq-package-#{System.unique_integer([:positive])}")

    package = Path.join(workspace, "rustq-package")
    File.rm_rf!(workspace)
    File.mkdir_p!(workspace)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(workspace) end)

    run!(root, "mix", ["hex.build", "--unpack", "--output", package])
    {:ok, workspace: workspace, package: package}
  end

  def copy_fixture!(fixture, workspace, name) do
    destination = Path.join(workspace, name)
    File.cp_r!(fixture, destination)
    destination
  end

  def package_env(package), do: [{"RUSTQ_PACKAGE_PATH", package}, {"MIX_ENV", "test"}]

  def run!(directory, command, args, env \\ []) do
    {output, status} =
      System.cmd(command, args,
        cd: directory,
        env: env,
        stderr_to_stdout: true
      )

    if status != 0 do
      ExUnit.Assertions.flunk(
        "#{command} #{Enum.join(args, " ")} failed in #{directory}:\n#{output}"
      )
    end

    output
  end
end
