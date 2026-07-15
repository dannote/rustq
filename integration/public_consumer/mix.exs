defmodule RustQPublicConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :rustq_public_consumer,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps: [
        {:rustq,
         path: System.fetch_env!("RUSTQ_PACKAGE_PATH"), only: [:dev, :test], runtime: false}
      ]
    ]
  end
end
