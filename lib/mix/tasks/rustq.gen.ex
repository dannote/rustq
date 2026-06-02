defmodule Mix.Tasks.Rustq.Gen do
  @moduledoc """
  Generates files declared in `rustq.exs`.

      mix rustq.gen
      mix rustq.gen --check
      mix rustq.gen --check-rust
      mix rustq.gen term_helpers
  """

  use Mix.Task

  @shortdoc "Generates files declared in rustq.exs"

  @impl Mix.Task
  def run(args) do
    {opts, names, invalid} =
      OptionParser.parse(args, strict: [check: :boolean, check_rust: :boolean, config: :string])

    if invalid != [] do
      Mix.raise("invalid rustq.gen options: #{inspect(invalid)}")
    end

    config = Keyword.get(opts, :config, "rustq.exs")

    config
    |> RustQ.Generated.load_manifest!()
    |> RustQ.Generated.sync_all!(
      check: Keyword.get(opts, :check, false),
      check_rust: Keyword.get(opts, :check_rust, false),
      only: names,
      shell: Mix.shell()
    )
  rescue
    error in RustQ.Generated.StaleError -> Mix.raise(Exception.message(error))
  end
end
