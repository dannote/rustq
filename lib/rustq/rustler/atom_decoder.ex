defmodule RustQ.Rustler.AtomDecoder do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @template ~R"""
  pub fn __rq_fn_name(value: __rq_input!()) -> __rq_result!() {
      match value {
          __rq_arms => unreachable!(),
      }
  }
  """

  @spec build(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def build(name, opts) do
    input = Keyword.get(opts, :input, :Atom)
    returns = Keyword.fetch!(opts, :returns)
    result = Keyword.get(opts, :result, "NifResult<#{Rust.type(returns)}>")
    atoms = Keyword.get(opts, :atoms, "atoms")
    unknown = Keyword.get(opts, :unknown, "Err(rustler::Error::BadArg)")

    arms =
      opts
      |> Keyword.fetch!(:cases)
      |> Enum.map(fn {atom, value} ->
        Rust.arm("value if value == #{atoms}::#{atom}()", "Ok(#{Rust.type(value)})")
      end)
      |> Kernel.++([Rust.arm("_", unknown)])

    @template
    |> RustQ.render!("rustler_atom_decoder.rs",
      bind: [fn_name: name, input: Rust.expr(Rust.type(input)), result: Rust.expr(result)],
      splice: [arms: arms]
    )
    |> Rust.item()
  end
end
