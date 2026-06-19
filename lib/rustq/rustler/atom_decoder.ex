defmodule RustQ.Rustler.AtomDecoder do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  @spec build(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def build(name, opts) do
    input = Keyword.get(opts, :input, :Atom)
    returns = Keyword.fetch!(opts, :returns)
    result = Keyword.get(opts, :result, "NifResult<#{Rust.type(returns)}>")
    atoms = Keyword.get(opts, :atoms, "atoms")
    unknown = Keyword.get(opts, :unknown, "Err(rustler::Error::BadArg)")

    cases =
      Keyword.get_lazy(opts, :cases, fn ->
        descriptor_cases(Keyword.fetch!(opts, :descriptor), returns)
      end)

    build_ast(name, input, result, atoms, unknown, cases)
  end

  defp build_ast(name, input, result, atoms, unknown, cases) do
    function = %AST.Function{
      name: ident_atom(name),
      vis: :pub,
      args: [A.function_arg(:value, Rust.type(input))],
      returns: result,
      body: [
        A.return_stmt(%AST.Match{expr: A.var(:value), arms: atom_arms(cases, atoms, unknown)})
      ]
    }

    Rust.ast_item(function)
  end

  defp atom_arms(cases, atoms, unknown) do
    module = atoms |> to_string() |> A.path_parts() |> Enum.map(&RustQ.Atom.identifier!/1)

    Enum.map(cases, fn {atom, value} ->
      %AST.Arm{
        pattern: %AST.PatAtomGuard{name: ident_atom(atom), module: module},
        body: [A.return_stmt(A.ok(rust_value_expr(value)))]
      }
    end) ++
      [
        unknown_arm(unknown)
      ]
  end

  defp ident_atom(value) when is_atom(value), do: value
  defp ident_atom(value) when is_binary(value), do: RustQ.Atom.identifier!(value)

  defp rust_value_expr(%{__struct__: _module} = value) do
    if AST.expr_node?(value), do: value, else: value |> Rust.type() |> A.path()
  end

  defp rust_value_expr(value), do: value |> Rust.type() |> A.path()

  defp unknown_arm("Err(rustler::Error::BadArg)"), do: A.badarg_arm()

  defp unknown_arm(%{__struct__: _module} = expr) do
    if AST.expr_node?(expr) do
      %AST.Arm{pattern: %AST.PatWildcard{}, body: [A.return_stmt(expr)]}
    else
      raise ArgumentError, "expected RustQ expression AST for unknown arm, got: #{inspect(expr)}"
    end
  end

  defp unknown_arm(unknown) when is_binary(unknown) do
    %AST.Arm{pattern: %AST.PatWildcard{}, body: [A.return_stmt(A.escape_expr(unknown))]}
  end

  defp descriptor_cases(%RustQ.NativeEnumDescriptor{} = descriptor, returns) do
    return_parts = returns |> Rust.type() |> A.path_parts()

    Enum.map(RustQ.NativeEnumDescriptor.variants(descriptor), fn {atom, variant} ->
      {atom, A.path(return_parts ++ [variant])}
    end)
  end
end
