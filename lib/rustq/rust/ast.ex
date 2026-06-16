defmodule RustQ.Rust.AST do
  @moduledoc """
  Small Rust AST/IR used by macro frontends before final RustQ validation.

  This is intentionally much smaller than Rust's full grammar. It captures the
  Rust-shaped nodes that `RustQ.Meta.defrust/2` can produce from valid Elixir
  AST, then renders them only at the final fragment-validation boundary.
  """

  defmodule Function do
    @moduledoc false
    defstruct [:name, args: [], returns: nil, body: [], lifetime: nil]
  end

  defmodule Let do
    @moduledoc false
    defstruct [:pattern, :expr, mutable: false]
  end

  defmodule ExprStmt do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule Return do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule Var do
    @moduledoc false
    defstruct [:name]
  end

  defmodule Path do
    @moduledoc false
    defstruct [:parts]
  end

  defmodule Field do
    @moduledoc false
    defstruct [:receiver, :field]
  end

  defmodule PathCall do
    @moduledoc false
    defstruct [:path, args: []]
  end

  defmodule MethodCall do
    @moduledoc false
    defstruct [:receiver, :method, args: []]
  end

  defmodule LocalCall do
    @moduledoc false
    defstruct [:name, args: []]
  end

  defmodule Ref do
    @moduledoc false
    defstruct [:expr, mutable: false]
  end

  defmodule Try do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule Tuple do
    @moduledoc false
    defstruct [:values]
  end

  defmodule Literal do
    @moduledoc false
    defstruct [:value]
  end

  defmodule AtomValue do
    @moduledoc false
    defstruct [:name]
  end

  defmodule None do
    @moduledoc false
    defstruct []
  end

  defmodule Some do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule Ok do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule Err do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule NifRaiseAtom do
    @moduledoc false
    defstruct [:name]
  end

  defmodule Match do
    @moduledoc false
    defstruct [:expr, arms: []]
  end

  defmodule Arm do
    @moduledoc false
    defstruct [:pattern, body: []]
  end

  defmodule PatVar do
    @moduledoc false
    defstruct [:name]
  end

  defmodule PatWildcard do
    @moduledoc false
    defstruct []
  end

  defmodule PatNone do
    @moduledoc false
    defstruct []
  end

  defmodule PatSome do
    @moduledoc false
    defstruct [:pattern]
  end

  defmodule PatAtomGuard do
    @moduledoc false
    defstruct [:name]
  end

  defmodule PatTuple do
    @moduledoc false
    defstruct [:patterns]
  end

  def render_function(%Function{} = function) do
    args = Enum.map_join(function.args, ", ", fn {name, type} -> "#{name}: #{type}" end)
    lifetime = if function.lifetime, do: "<'#{function.lifetime}>", else: ""

    [
      "fn ",
      Atom.to_string(function.name),
      lifetime,
      "(",
      args,
      ") -> ",
      function.returns,
      " {\n",
      function.body |> Enum.map(&render_stmt/1) |> Enum.join("\n") |> indent(),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  def render_stmt(%Let{} = stmt) do
    mut = if stmt.mutable, do: "mut ", else: ""
    ["let ", mut, render_pattern(stmt.pattern), " = ", render_expr(stmt.expr), ";"]
  end

  def render_stmt(%ExprStmt{} = stmt), do: [render_expr(stmt.expr), ";"]
  def render_stmt(%Return{} = stmt), do: render_expr(stmt.expr)

  def render_expr(%Var{name: name}), do: Atom.to_string(name)
  def render_expr(%Path{parts: parts}), do: Enum.map_join(parts, "::", &to_string/1)

  def render_expr(%Field{receiver: receiver, field: field}),
    do: [render_expr(receiver), ".", to_string(field)]

  def render_expr(%PathCall{path: path, args: args}) do
    [render_expr(path), "(", render_args(args), ")"]
  end

  def render_expr(%MethodCall{receiver: receiver, method: method, args: args}) do
    [render_expr(receiver), ".", to_string(method), "(", render_args(args), ")"]
  end

  def render_expr(%LocalCall{name: name, args: args}),
    do: [to_string(name), "(", render_args(args), ")"]

  def render_expr(%Ref{expr: expr, mutable: false}), do: ["&", render_expr(expr)]
  def render_expr(%Ref{expr: expr, mutable: true}), do: ["&mut ", render_expr(expr)]
  def render_expr(%Try{expr: expr}), do: [render_expr(expr), "?"]
  def render_expr(%Tuple{values: values}), do: ["(", render_args(values), ")"]
  def render_expr(%Literal{value: value}) when is_binary(value), do: inspect(value)

  def render_expr(%Literal{value: value}) when is_integer(value) or is_float(value),
    do: to_string(value)

  def render_expr(%Literal{value: true}), do: "true"
  def render_expr(%Literal{value: false}), do: "false"
  def render_expr(%AtomValue{name: name}), do: ["atoms::", Atom.to_string(name), "()"]
  def render_expr(%None{}), do: "None"
  def render_expr(%Some{expr: expr}), do: ["Some(", render_expr(expr), ")"]
  def render_expr(%Ok{expr: nil}), do: "Ok(())"
  def render_expr(%Ok{expr: expr}), do: ["Ok(", render_expr(expr), ")"]
  def render_expr(%Err{expr: expr}), do: ["Err(", render_expr(expr), ")"]

  def render_expr(%NifRaiseAtom{name: name}) do
    ~s|rustler::Error::RaiseAtom("#{name}")|
  end

  def render_expr(%Match{} = match) do
    arms = match.arms |> Enum.map(&render_arm/1) |> Enum.join("\n")
    ["match ", render_expr(match.expr), " {\n", indent(arms), "\n}"]
  end

  def render_arm(%Arm{pattern: pattern, body: body}) do
    rendered_body = body |> Enum.map(&render_stmt/1) |> Enum.join("\n")
    [render_pattern(pattern), " => {\n", indent(rendered_body), "\n},"]
  end

  def render_pattern(%PatVar{name: name}), do: Atom.to_string(name)
  def render_pattern(%PatWildcard{}), do: "_"
  def render_pattern(%PatNone{}), do: "None"
  def render_pattern(%PatSome{pattern: pattern}), do: ["Some(", render_pattern(pattern), ")"]

  def render_pattern(%PatAtomGuard{name: name}),
    do: ["value if value == atoms::", Atom.to_string(name), "()"]

  def render_pattern(%PatTuple{patterns: patterns}) do
    ["(", patterns |> Enum.map(&render_pattern/1) |> Enum.intersperse(", "), ")"]
  end

  defp render_args(args), do: args |> Enum.map(&render_expr/1) |> Enum.intersperse(", ")

  defp indent(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end
end
