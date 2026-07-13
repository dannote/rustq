defmodule RustQ.Rustler.Atom do
  @moduledoc """
  Generates Rustler atom declarations, decoders, dispatchers, and cached atom helpers.

  Decoder and dispatch helpers prefer RustQ AST. Options such as `:on`, `:cases`,
  and `:unknown` may accept explicit Rust expression strings for advanced caller
  escape hatches; prefer AST expressions when composing generated code.
  """

  use RustQ.Meta

  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Native.EnumDescriptor
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I
  alias RustQ.Rust.AST.TypeBuilder, as: T
  alias RustQ.Rust.Identifier
  alias RustQ.Type, as: R

  import RustQ.Rust.AST.ItemBuilder, only: [function: 3, static: 3]

  require A
  require I

  @doc "Builds a `rustler::atoms!` declaration, optionally wrapped in a module."
  @spec declaration([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) ::
          AST.MacroItemCall.t() | AST.Module.t()
  def declaration(atoms, opts \\ []) do
    item = A.macro_item_call([:rustler, :atoms], atoms)

    case Keyword.get(opts, :module, :atoms) do
      false -> item
      module -> A.module(module, [item])
    end
  end

  @doc "Builds a function that decodes Rustler atoms into Rust values."
  @spec decoder(atom() | String.t(), keyword()) :: AST.Function.t()
  def decoder(name, opts) do
    input = Keyword.get(opts, :input, :Atom)
    returns = Keyword.fetch!(opts, :returns)
    result = Keyword.get(opts, :result, T.nif_result(returns))
    atoms = Keyword.get(opts, :atoms, "atoms")
    unknown = Keyword.get(opts, :unknown, "Err(rustler::Error::BadArg)")

    cases =
      Keyword.get_lazy(opts, :cases, fn ->
        descriptor_cases(Keyword.fetch!(opts, :descriptor), returns)
      end)

    decoder_ast(name, input, result, atoms, unknown, cases)
  end

  @doc "Builds a function that dispatches an expression by atom value."
  @spec dispatch(atom() | String.t(), keyword()) :: AST.Function.t()
  def dispatch(name, opts) do
    atoms = Keyword.get(opts, :atoms, "atoms")
    unknown = Keyword.get(opts, :unknown, A.ok())

    %AST.Function{
      name: ident_atom(name),
      args: Keyword.get(opts, :args, []),
      returns: Keyword.get(opts, :returns, "NifResult<()>"),
      body: [
        A.let(:value, dispatch_expr(Keyword.fetch!(opts, :on))),
        A.return_stmt(%AST.Match{
          expr: A.var(:value),
          arms: dispatch_arms(Keyword.fetch!(opts, :cases), atoms, unknown)
        })
      ],
      vis: Keyword.get(opts, :vis),
      lifetimes: List.wrap(Keyword.get(opts, :lifetimes, [])),
      attrs: Keyword.get(opts, :attrs, [])
    }
  end

  @doc "Builds `OnceLock<Atom>` declarations and cached atom accessors."
  @spec cached([atom() | String.t() | {atom() | String.t(), String.t()}], keyword()) :: [
          AST.item()
        ]
  def cached(atoms, opts \\ []) do
    include_helpers? = Keyword.get(opts, :helpers, true)

    atoms = Enum.map(atoms, &atom_spec/1)

    helper_items =
      if include_helpers? do
        [MetaAST.function!(__MODULE__, :cached_atom)]
      else
        []
      end

    helper_items ++ Enum.flat_map(atoms, &atom_items/1)
  end

  @spec cached_atom(R.path(:Env), R.ref(R.raw(:"OnceLock<Atom>")), R.ref(R.path(:str))) ::
          atom()
  defrust cached_atom(env, cell, name) do
    deref(cell.get_or_init(fn -> Atom.from_str(env, name).unwrap() end))
  end

  defp decoder_ast(name, input, result, atoms, unknown, cases) do
    %AST.Function{
      name: ident_atom(name),
      vis: :pub,
      args: [A.function_arg(:value, T.type(input))],
      returns: result,
      body: [
        A.return_stmt(%AST.Match{expr: A.var(:value), arms: atom_arms(cases, atoms, unknown)})
      ]
    }
  end

  defp atom_arms(cases, atoms, unknown) do
    module = atoms |> to_string() |> A.path_parts() |> Enum.map(&Identifier.atom!/1)

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

  defp dispatch_arms(cases, atoms, unknown) do
    module = atoms |> to_string() |> A.path_parts() |> Enum.map(&Identifier.atom!/1)

    Enum.map(cases, fn {atom, call} ->
      %AST.Arm{
        pattern: %AST.PatAtomGuard{name: ident_atom(atom), module: module},
        body: [A.return_stmt(dispatch_expr(call))]
      }
    end) ++
      [
        %AST.Arm{pattern: %AST.PatWildcard{}, body: [A.return_stmt(dispatch_expr(unknown))]}
      ]
  end

  defp dispatch_expr(%{__struct__: _module} = expr) do
    if AST.expr_node?(expr) do
      expr
    else
      raise ArgumentError, "expected RustQ expression AST, got: #{inspect(expr)}"
    end
  end

  defp dispatch_expr(source) when is_binary(source), do: A.escape_expr(source)
  defp dispatch_expr(value), do: A.expr(value)

  defp ident_atom(value) when is_atom(value), do: value
  defp ident_atom(value) when is_binary(value), do: Identifier.atom!(value)

  defp rust_value_expr(%{__struct__: _module} = value) do
    if AST.expr_node?(value) do
      value
    else
      raise ArgumentError, "expected RustQ expression AST, got: #{inspect(value)}"
    end
  end

  defp rust_value_expr(value), do: A.path(value)

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

  defp descriptor_cases(%EnumDescriptor{} = descriptor, returns) do
    return_parts = A.path_parts(returns)

    Enum.map(EnumDescriptor.variants(descriptor), fn {atom, variant} ->
      {atom, A.path(return_parts ++ [variant])}
    end)
  end

  defp atom_items({name, value}) do
    static_name = static_name(name)

    [
      static(
        Identifier.atom!(static_name),
        "OnceLock<Atom>",
        A.path_call([:OnceLock, :new])
      ),
      function Identifier.atom!("#{name}_atom"), args: [env: "Env"], returns: "Atom" do
        A.return(
          A.call(:cached_atom, [
            A.var(:env),
            A.ref(A.var(Identifier.atom!(static_name))),
            A.lit(value)
          ])
        )
      end
    ]
  end

  defp atom_spec(name) when is_atom(name), do: {name, Atom.to_string(name)}
  defp atom_spec(name) when is_binary(name), do: {name, name}

  defp atom_spec({name, value}) when (is_atom(name) or is_binary(name)) and is_binary(value),
    do: {name, value}

  defp static_name(name) do
    name
    |> to_string()
    |> Macro.underscore()
    |> String.upcase()
    |> Kernel.<>("_ATOM")
  end
end
