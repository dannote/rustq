defmodule RustQ.Rust.AST do
  @moduledoc """
  Small Rust AST/IR used by macro frontends before final RustQ validation.

  This is intentionally much smaller than Rust's full grammar. It captures the
  Rust-shaped nodes that `RustQ.Meta.defrust/2` can produce from valid Elixir
  AST, then renders them only at the final fragment-validation boundary.
  """

  defmodule Function do
    @moduledoc false
    defstruct [:name, args: [], returns: nil, body: [], lifetime: nil, vis: nil]
  end

  defmodule Struct do
    @moduledoc false
    defstruct [:name, fields: [], vis: nil, derive: [], lifetime: nil]
  end

  defmodule StructField do
    @moduledoc false
    defstruct [:name, :type, vis: nil]
  end

  defmodule Enum do
    @moduledoc false
    defstruct [:name, variants: [], vis: nil, derive: []]
  end

  defmodule EnumVariant do
    @moduledoc false
    defstruct [:name]
  end

  defmodule TypePath do
    @moduledoc false
    defstruct [:parts, lifetimes: []]
  end

  defmodule TypeRef do
    @moduledoc false
    defstruct [:inner, mutable: false, lifetime: nil]
  end

  defmodule TypeOption do
    @moduledoc false
    defstruct [:inner]
  end

  defmodule TypeResult do
    @moduledoc false
    defstruct [:ok, :error]
  end

  defmodule TypeNifResult do
    @moduledoc false
    defstruct [:inner]
  end

  defmodule TypeVec do
    @moduledoc false
    defstruct [:inner]
  end

  defmodule TypeUnit do
    @moduledoc false
    defstruct []
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

  def render_item_native(%Function{} = item), do: render_native(item, &render_function/1)
  def render_item_native(%Struct{} = item), do: render_native(item, &render_struct/1)
  def render_item_native(%Enum{} = item), do: render_native(item, &render_enum/1)

  def render_function_native(%Function{} = function), do: render_item_native(function)

  defp render_native(item, fallback) do
    RustQ.Native.render_ast(item)
  rescue
    _error -> fallback.(item)
  catch
    :exit, _reason -> fallback.(item)
  end

  def render_function(%Function{} = function) do
    args =
      Elixir.Enum.map_join(function.args, ", ", fn {name, type} ->
        "#{name}: #{render_type(type)}"
      end)

    lifetime = if function.lifetime, do: "<'#{function.lifetime}>", else: ""

    [
      render_vis(function.vis),
      "fn ",
      Atom.to_string(function.name),
      lifetime,
      "(",
      args,
      ") -> ",
      render_type(function.returns),
      " {\n",
      function.body |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n") |> indent(),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  def render_struct(%Struct{} = struct) do
    derive = render_derive(struct.derive)
    vis = render_vis(struct.vis)
    lifetime = if struct.lifetime, do: "<'#{struct.lifetime}>", else: ""
    fields = struct.fields |> Elixir.Enum.map(&render_struct_field/1) |> Elixir.Enum.join("\n")

    [
      derive,
      vis,
      "struct ",
      Atom.to_string(struct.name),
      lifetime,
      " {\n",
      fields |> indent(),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  def render_struct_field(%StructField{} = field) do
    [render_vis(field.vis), Atom.to_string(field.name), ": ", render_type(field.type), ","]
  end

  def render_enum(%Enum{} = enum) do
    derive = render_derive(enum.derive)
    vis = render_vis(enum.vis)
    variants = enum.variants |> Elixir.Enum.map(&render_enum_variant/1) |> Elixir.Enum.join("\n")

    [derive, vis, "enum ", Atom.to_string(enum.name), " {\n", variants |> indent(), "\n}"]
    |> IO.iodata_to_binary()
  end

  def render_enum_variant(%EnumVariant{} = variant), do: [Atom.to_string(variant.name), ","]

  def render_type(type) when is_binary(type), do: type
  def render_type(%TypeUnit{}), do: "()"

  def render_type(%TypePath{parts: parts, lifetimes: lifetimes}) do
    base = Elixir.Enum.map_join(parts, "::", &to_string/1)

    case lifetimes do
      [] ->
        base

      lifetimes ->
        [
          base,
          "<",
          lifetimes |> Elixir.Enum.map(&["'", to_string(&1)]) |> Elixir.Enum.intersperse(", "),
          ">"
        ]
    end
  end

  def render_type(%TypeRef{inner: inner, mutable: mutable, lifetime: lifetime}) do
    mut = if mutable, do: "mut ", else: ""
    lifetime = if lifetime, do: ["'", to_string(lifetime), " "], else: []
    ["&", lifetime, mut, render_type(inner)]
  end

  def render_type(%TypeOption{inner: inner}), do: ["Option<", render_type(inner), ">"]

  def render_type(%TypeResult{ok: ok, error: error}),
    do: ["Result<", render_type(ok), ", ", render_type(error), ">"]

  def render_type(%TypeNifResult{inner: inner}), do: ["NifResult<", render_type(inner), ">"]
  def render_type(%TypeVec{inner: inner}), do: ["Vec<", render_type(inner), ">"]

  def render_stmt(%Let{} = stmt) do
    mut = if stmt.mutable, do: "mut ", else: ""
    ["let ", mut, render_pattern(stmt.pattern), " = ", render_expr(stmt.expr), ";"]
  end

  def render_stmt(%ExprStmt{} = stmt), do: [render_expr(stmt.expr), ";"]
  def render_stmt(%Return{} = stmt), do: render_expr(stmt.expr)

  def render_expr(%Var{name: name}), do: Atom.to_string(name)
  def render_expr(%Path{parts: parts}), do: Elixir.Enum.map_join(parts, "::", &to_string/1)

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
    arms = match.arms |> Elixir.Enum.map(&render_arm/1) |> Elixir.Enum.join("\n")
    ["match ", render_expr(match.expr), " {\n", indent(arms), "\n}"]
  end

  def render_arm(%Arm{pattern: pattern, body: body}) do
    rendered_body = body |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")
    [render_pattern(pattern), " => {\n", indent(rendered_body), "\n},"]
  end

  def render_pattern(%PatVar{name: name}), do: Atom.to_string(name)
  def render_pattern(%PatWildcard{}), do: "_"
  def render_pattern(%PatNone{}), do: "None"
  def render_pattern(%PatSome{pattern: pattern}), do: ["Some(", render_pattern(pattern), ")"]

  def render_pattern(%PatAtomGuard{name: name}),
    do: ["value if value == atoms::", Atom.to_string(name), "()"]

  def render_pattern(%PatTuple{patterns: patterns}) do
    ["(", patterns |> Elixir.Enum.map(&render_pattern/1) |> Elixir.Enum.intersperse(", "), ")"]
  end

  defp render_args(args),
    do: args |> Elixir.Enum.map(&render_expr/1) |> Elixir.Enum.intersperse(", ")

  defp render_derive([]), do: []

  defp render_derive(values) do
    [
      "#[derive(",
      values |> Elixir.Enum.map(&to_string/1) |> Elixir.Enum.intersperse(", "),
      ")]\n"
    ]
  end

  defp render_vis(:pub), do: "pub "
  defp render_vis(:crate), do: "pub(crate) "
  defp render_vis(nil), do: []

  defp indent(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Elixir.Enum.map_join("\n", &("    " <> &1))
  end
end
