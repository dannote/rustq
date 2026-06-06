defmodule RustQ.Rustler.AtomDispatch do
  @moduledoc false

  alias RustQ.Rust

  @spec build(atom() | String.t(), keyword()) :: Rust.Function.t()
  def build(name, opts) do
    value = Keyword.fetch!(opts, :on)
    atoms = Keyword.get(opts, :atoms, "atoms")
    unknown = Keyword.get(opts, :unknown, "Ok(())")

    arms =
      opts
      |> Keyword.fetch!(:cases)
      |> Enum.map(fn {atom_name, call} ->
        "value if value == #{atoms}::#{atom_name}() => #{call},"
      end)
      |> Kernel.++(["_ => #{unknown},"])

    body = [
      "let value = ",
      value,
      ";\n\nmatch value {\n",
      Enum.map(arms, &["    ", &1, "\n"]),
      "}"
    ]

    Rust.fn(name,
      args: Keyword.get(opts, :args, []),
      returns: Keyword.get(opts, :returns, "NifResult<()>"),
      body: body,
      vis: Keyword.get(opts, :vis),
      lifetime: Keyword.get(opts, :lifetime),
      attrs: Keyword.get(opts, :attrs, [])
    )
  end
end
