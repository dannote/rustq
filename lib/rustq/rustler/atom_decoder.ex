defmodule RustQ.Rustler.AtomDecoder do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

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

    if unknown == "Err(rustler::Error::BadArg)" do
      build_ast(name, input, result, atoms, Keyword.fetch!(opts, :cases))
    else
      build_template(name, input, result, atoms, unknown, opts)
    end
  end

  defp build_ast(name, input, result, atoms, cases) do
    function = %AST.Function{
      name: ident_atom(name),
      vis: :pub,
      args: [A.function_arg(:value, Rust.type(input))],
      returns: result,
      body: [
        A.return_stmt(%AST.Match{expr: A.var(:value), arms: atom_arms(cases, atoms)})
      ]
    }

    Rust.item(AST.render_item_native(function))
  end

  defp atom_arms(cases, atoms) do
    module = atoms |> to_string() |> String.split("::") |> Enum.map(&String.to_atom/1)

    Enum.map(cases, fn {atom, value} ->
      %AST.Arm{
        pattern: %AST.PatAtomGuard{name: ident_atom(atom), module: module},
        body: [A.return_stmt(A.ok(rust_value_expr(value)))]
      }
    end) ++
      [
        %AST.Arm{
          pattern: A.wildcard(),
          body: [A.return_stmt(A.err(A.path([:rustler, :Error, :BadArg])))]
        }
      ]
  end

  defp ident_atom(value) when is_atom(value), do: value
  defp ident_atom(value) when is_binary(value), do: String.to_atom(value)

  defp rust_value_expr(value) do
    value
    |> Rust.type()
    |> String.split("::")
    |> A.path()
  end

  defp build_template(name, input, result, atoms, unknown, opts) do
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
