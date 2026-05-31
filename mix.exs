defmodule RustQ.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elixir-vibe/rustq"

  def project do
    [
      app: :rustq,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: "Rust templates and quasiquoting for Elixir",
      aliases: aliases(),
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      {:rustler, "~> 0.37", runtime: false},
      {:vibe_kit, "~> 0.1", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "rust.fmt --check",
        "rust.check",
        "rust.clippy",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ],
      "rust.fmt": &rust_fmt/1,
      "rust.check": &rust_check/1,
      "rust.clippy": &rust_clippy/1
    ]
  end

  defp rust_fmt(args) do
    rust_cmd(["fmt", "--manifest-path", "native/rustq_nif/Cargo.toml"] ++ args)
  end

  defp rust_check(_args) do
    rust_cmd(["check", "--manifest-path", "native/rustq_nif/Cargo.toml"])
  end

  defp rust_clippy(_args) do
    rust_cmd(["clippy", "--manifest-path", "native/rustq_nif/Cargo.toml", "--", "-D", "warnings"])
  end

  defp rust_cmd(args) do
    {_, status} = System.cmd("cargo", args, into: IO.stream(), stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("cargo #{Enum.join(args, " ")} failed")
    end
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
