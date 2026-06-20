defmodule RustQ.Rustler.Decode do
  @moduledoc """
  AST helpers for composing Rustler term decoding expressions.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.PatternBuilder, as: P

  def atom(name, opts \\ []), do: A.atom(name, opts)

  def opt_decode(helper, opts_var, atom_name, opts \\ []) do
    %AST.Try{expr: A.call(helper, [opts_var, atom(atom_name, Keyword.take(opts, [:module]))])}
  end

  def require_some(expression),
    do: %AST.Try{expr: A.method(expression, :ok_or, [A.path([:rustler, :Error, :BadArg])])}

  def required_opt_decode(helper, opts_var, atom_name, opts \\ []) do
    helper_call = A.call(helper, [opts_var, atom(atom_name, Keyword.take(opts, [:module]))])

    helper_call
    |> then(&%AST.Try{expr: &1})
    |> require_some()
  end

  def required_term(opts_var, atom_name, opts \\ []) do
    opts_var
    |> call_opt_term(atom_name, opts)
    |> require_some()
  end

  def required_term_decode(opts_var, atom_name, type, opts \\ []) do
    opts_var
    |> required_term(atom_name, opts)
    |> A.method(:decode, [], generics: [type])
    |> then(&%AST.Try{expr: &1})
  end

  def optional_term_decode(opts_var, atom_name, type, opts \\ []) do
    %AST.Match{
      expr: call_opt_term(opts_var, atom_name, opts),
      arms: [
        %AST.Arm{
          pattern: P.some(:term),
          body: [
            A.return_stmt(A.some(%AST.Try{expr: A.method(:term, :decode, [], generics: [type])}))
          ]
        },
        %AST.Arm{pattern: P.none(), body: [A.return_stmt(A.none())]}
      ]
    }
  end

  defp call_opt_term(opts_var, atom_name, opts),
    do: A.call(:opt_term, [opts_var, atom(atom_name, Keyword.take(opts, [:module]))])
end
