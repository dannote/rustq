defmodule RustQ.Rust.AST do
  @moduledoc """
  Small Rust AST/IR used by macro frontends before final RustQ validation.

  This is intentionally much smaller than Rust's full grammar. It captures the
  Rust-shaped nodes that `RustQ.Meta.defrust/2` can produce from valid Elixir
  AST, then renders them only at the final fragment-validation boundary.
  """

  @type item ::
          Use.t()
          | Module.t()
          | Const.t()
          | MacroItem.t()
          | Function.t()
          | Struct.t()
          | Enum.t()

  @type stmt :: Let.t() | ExprStmt.t() | Return.t()

  @type expr ::
          Var.t()
          | Path.t()
          | Field.t()
          | PathCall.t()
          | MethodCall.t()
          | StructLiteral.t()
          | LocalCall.t()
          | Ref.t()
          | Try.t()
          | Tuple.t()
          | Literal.t()
          | TokenMacro.t()
          | AtomValue.t()
          | None.t()
          | Some.t()
          | Ok.t()
          | Err.t()
          | NifRaiseAtom.t()
          | Match.t()
          | If.t()
          | BinaryOp.t()

  @type type ::
          TypePath.t()
          | TypeRef.t()
          | TypeOption.t()
          | TypeResult.t()
          | TypeNifResult.t()
          | TypeVec.t()
          | TypeUnit.t()

  @type pat ::
          PatVar.t()
          | PatWildcard.t()
          | PatPath.t()
          | PatLiteral.t()
          | PatNone.t()
          | PatSome.t()
          | PatAtomGuard.t()
          | PatTuple.t()
          | PatOk.t()
          | PatErr.t()
          | PatPathTuple.t()
          | PatStruct.t()

  @type vis :: :pub | :crate | nil

  import RustQ.Rust.AST.NodeDSL

  defnode(Use, :item, [:tree], type: quote(do: %__MODULE__{tree: String.t()}))

  defnode(Module, :item, [:name, items: [], vis: nil],
    type:
      quote(
        do: %__MODULE__{name: atom(), items: [RustQ.Rust.AST.item()], vis: RustQ.Rust.AST.vis()}
      )
  )

  defnode(Const, :item, [:name, :type, :expr, vis: nil],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          type: RustQ.Rust.AST.type() | String.t(),
          expr: RustQ.Rust.AST.expr(),
          vis: RustQ.Rust.AST.vis()
        }
      )
  )

  defnode(MacroItem, :item, [:source], type: quote(do: %__MODULE__{source: String.t()}))

  defnode(Function, :item, [:name, args: [], returns: nil, body: [], lifetime: nil, vis: nil],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          args: [{atom(), RustQ.Rust.AST.type() | String.t()}],
          returns: RustQ.Rust.AST.type() | String.t(),
          body: [RustQ.Rust.AST.stmt()],
          lifetime: atom() | nil,
          vis: RustQ.Rust.AST.vis()
        }
      )
  )

  defnode(Struct, :item, [:name, fields: [], vis: nil, derive: [], lifetime: nil],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          fields: [RustQ.Rust.AST.StructField.t()],
          vis: RustQ.Rust.AST.vis(),
          derive: [atom()],
          lifetime: atom() | nil
        }
      )
  )

  defnode(StructField, :field, [:name, :type, vis: nil],
    type:
      quote(do: %__MODULE__{name: atom(), type: RustQ.Rust.AST.type(), vis: RustQ.Rust.AST.vis()})
  )

  defnode(Enum, :item, [:name, variants: [], vis: nil, derive: []],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          variants: [RustQ.Rust.AST.EnumVariant.t()],
          vis: RustQ.Rust.AST.vis(),
          derive: [atom()]
        }
      )
  )

  defnode(EnumVariant, :field, [:name, tuple: []],
    type: quote(do: %__MODULE__{name: atom(), tuple: [RustQ.Rust.AST.type()]})
  )

  defnode(TypePath, :type, [:parts, lifetimes: [], generics: []],
    type:
      quote(
        do: %__MODULE__{
          parts: [atom() | String.t()],
          lifetimes: [atom()],
          generics: [RustQ.Rust.AST.type()]
        }
      )
  )

  defnode(TypeRef, :type, [:inner, mutable: false, lifetime: nil],
    type:
      quote(
        do: %__MODULE__{inner: RustQ.Rust.AST.type(), mutable: boolean(), lifetime: atom() | nil}
      )
  )

  defnode(TypeOption, :type, [:inner], type: quote(do: %__MODULE__{inner: RustQ.Rust.AST.type()}))

  defnode(TypeResult, :type, [:ok, :error],
    type: quote(do: %__MODULE__{ok: RustQ.Rust.AST.type(), error: RustQ.Rust.AST.type()})
  )

  defnode(TypeNifResult, :type, [:inner],
    type: quote(do: %__MODULE__{inner: RustQ.Rust.AST.type()})
  )

  defnode(TypeVec, :type, [:inner], type: quote(do: %__MODULE__{inner: RustQ.Rust.AST.type()}))

  defnode(TypeUnit, :type, [], type: quote(do: %__MODULE__{}))

  defnode(Let, :stmt, [:pattern, :expr, mutable: false, type: nil],
    type:
      quote(
        do: %__MODULE__{
          pattern: RustQ.Rust.AST.pat(),
          expr: RustQ.Rust.AST.expr(),
          mutable: boolean(),
          type: RustQ.Rust.AST.type() | String.t() | nil
        }
      )
  )

  defnode(ExprStmt, :stmt, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(Return, :stmt, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(Var, :expr, [:name], type: quote(do: %__MODULE__{name: atom()}))

  defnode(Path, :expr, [:parts], type: quote(do: %__MODULE__{parts: [atom() | String.t()]}))

  defnode(Field, :expr, [:receiver, :field],
    type: quote(do: %__MODULE__{receiver: RustQ.Rust.AST.expr(), field: atom()})
  )

  defnode(PathCall, :expr, [:path, args: []],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), args: [RustQ.Rust.AST.expr()]})
  )

  defnode(MethodCall, :expr, [:receiver, :method, args: []],
    type:
      quote(
        do: %__MODULE__{
          receiver: RustQ.Rust.AST.expr(),
          method: atom(),
          args: [RustQ.Rust.AST.expr()]
        }
      )
  )

  defnode(StructLiteral, :expr, [:path, fields: []],
    type:
      quote(
        do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), fields: [{atom(), RustQ.Rust.AST.expr()}]}
      )
  )

  defnode(LocalCall, :expr, [:name, args: []],
    type: quote(do: %__MODULE__{name: atom(), args: [RustQ.Rust.AST.expr()]})
  )

  defnode(Ref, :expr, [:expr, mutable: false],
    type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr(), mutable: boolean()})
  )

  defnode(Try, :expr, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(Tuple, :expr, [:values], type: quote(do: %__MODULE__{values: [RustQ.Rust.AST.expr()]}))

  defnode(Literal, :expr, [:value],
    type: quote(do: %__MODULE__{value: String.t() | integer() | float() | boolean()})
  )

  defnode(TokenMacro, :expr, [:path, :tokens],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), tokens: String.t()})
  )

  defnode(AtomValue, :expr, [:name], type: quote(do: %__MODULE__{name: atom()}))

  defnode(None, :expr, [], type: quote(do: %__MODULE__{}))

  defnode(Some, :expr, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(Ok, :expr, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr() | nil}))

  defnode(Err, :expr, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(NifRaiseAtom, :expr, [:name], type: quote(do: %__MODULE__{name: atom()}))

  defnode(Match, :expr, [:expr, arms: []],
    type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr(), arms: [RustQ.Rust.AST.Arm.t()]})
  )

  defnode(If, :expr, [:condition, then: [], else: []],
    type:
      quote(
        do: %__MODULE__{
          condition: RustQ.Rust.AST.expr(),
          then: [RustQ.Rust.AST.stmt()],
          else: [RustQ.Rust.AST.stmt()]
        }
      )
  )

  defnode(BinaryOp, :expr, [:left, :op, :right],
    type:
      quote(
        do: %__MODULE__{
          left: RustQ.Rust.AST.expr(),
          op: :eq | :and | :or,
          right: RustQ.Rust.AST.expr()
        }
      )
  )

  defnode(Arm, :field, [:pattern, body: []],
    type: quote(do: %__MODULE__{pattern: RustQ.Rust.AST.pat(), body: [RustQ.Rust.AST.stmt()]})
  )

  defnode(PatVar, :pat, [:name], type: quote(do: %__MODULE__{name: atom()}))

  defnode(PatWildcard, :pat, [], type: quote(do: %__MODULE__{}))

  defnode(PatPath, :pat, [:path], type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t()}))

  defnode(PatLiteral, :pat, [:value], type: quote(do: %__MODULE__{value: String.t() | atom()}))

  defnode(PatNone, :pat, [], type: quote(do: %__MODULE__{}))

  defnode(PatSome, :pat, [:pattern], type: quote(do: %__MODULE__{pattern: RustQ.Rust.AST.pat()}))

  defnode(PatAtomGuard, :pat, [:name], type: quote(do: %__MODULE__{name: atom()}))

  defnode(PatTuple, :pat, [:patterns],
    type: quote(do: %__MODULE__{patterns: [RustQ.Rust.AST.pat()]})
  )

  defnode(PatOk, :pat, [:pattern], type: quote(do: %__MODULE__{pattern: RustQ.Rust.AST.pat()}))

  defnode(PatErr, :pat, [:pattern], type: quote(do: %__MODULE__{pattern: RustQ.Rust.AST.pat()}))

  defnode(PatPathTuple, :pat, [:path, patterns: []],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), patterns: [RustQ.Rust.AST.pat()]})
  )

  defnode(PatStruct, :pat, [:path, fields: []],
    type:
      quote(
        do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), fields: [{atom(), RustQ.Rust.AST.pat()}]}
      )
  )

  def __rustq_ast_modules__ do
    [
      Use,
      Module,
      Const,
      MacroItem,
      Function,
      Struct,
      StructField,
      Enum,
      EnumVariant,
      TypePath,
      TypeRef,
      TypeOption,
      TypeResult,
      TypeNifResult,
      TypeVec,
      TypeUnit,
      Let,
      ExprStmt,
      Return,
      Var,
      Path,
      Field,
      PathCall,
      MethodCall,
      StructLiteral,
      LocalCall,
      Ref,
      Try,
      Tuple,
      Literal,
      TokenMacro,
      AtomValue,
      None,
      Some,
      Ok,
      Err,
      NifRaiseAtom,
      Match,
      If,
      BinaryOp,
      Arm,
      PatVar,
      PatWildcard,
      PatPath,
      PatLiteral,
      PatNone,
      PatSome,
      PatAtomGuard,
      PatTuple,
      PatOk,
      PatErr,
      PatPathTuple,
      PatStruct
    ]
  end

  def render_item_native(%Use{} = item), do: render_native(item, &render_use/1)
  def render_item_native(%Module{} = item), do: render_native(item, &render_module/1)
  def render_item_native(%Const{} = item), do: render_native(item, &render_const/1)
  def render_item_native(%MacroItem{} = item), do: render_native(item, &render_macro_item/1)
  def render_item_native(%Function{} = item), do: render_native(item, &render_function/1)
  def render_item_native(%Struct{} = item), do: render_native(item, &render_struct/1)
  def render_item_native(%Enum{} = item), do: render_native(item, &render_enum/1)

  def render_file_native(items) do
    items
    |> List.wrap()
    |> Elixir.Enum.map_join("\n", &render_item_native/1)
  end

  def render_function_native(%Function{} = function), do: render_item_native(function)

  defp render_native(item, fallback) do
    RustQ.Native.render_ast(item)
  rescue
    _error -> fallback.(item)
  catch
    :exit, _reason -> fallback.(item)
  end

  def render_use(%Use{tree: tree}), do: ["use ", tree, ";"]

  def render_module(%Module{} = module) do
    items = module.items |> Elixir.Enum.map(&render_item_native/1) |> Elixir.Enum.join("\n")

    [
      render_vis(module.vis),
      "mod ",
      Atom.to_string(module.name),
      " {\n",
      indent(items),
      "\n}"
    ]
  end

  def render_const(%Const{} = const) do
    [
      render_vis(const.vis),
      "const ",
      Atom.to_string(const.name),
      ": ",
      render_type(const.type),
      " = ",
      render_expr(const.expr),
      ";"
    ]
  end

  def render_macro_item(%MacroItem{source: source}), do: source

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

  def render_enum_variant(%EnumVariant{tuple: []} = variant),
    do: [Atom.to_string(variant.name), ","]

  def render_enum_variant(%EnumVariant{} = variant) do
    [
      Atom.to_string(variant.name),
      "(",
      variant.tuple |> Elixir.Enum.map(&render_type/1) |> Elixir.Enum.intersperse(", "),
      "),"
    ]
  end

  def render_type(type) when is_binary(type), do: type
  def render_type(%TypeUnit{}), do: "()"

  def render_type(%TypePath{parts: parts, lifetimes: lifetimes, generics: generics}) do
    base = Elixir.Enum.map_join(parts, "::", &to_string/1)

    generic_args =
      (lifetimes |> Elixir.Enum.map(&["'", to_string(&1)])) ++
        (generics |> Elixir.Enum.map(&render_type/1))

    case generic_args do
      [] -> base
      args -> [base, "<", Elixir.Enum.intersperse(args, ", "), ">"]
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
    type = if stmt.type, do: [": ", render_type(stmt.type)], else: []
    ["let ", mut, render_pattern(stmt.pattern), type, " = ", render_expr(stmt.expr), ";"]
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

  def render_expr(%StructLiteral{path: path, fields: fields}) do
    rendered_fields =
      fields
      |> Elixir.Enum.map(fn {name, expr} -> [to_string(name), ": ", render_expr(expr)] end)
      |> Elixir.Enum.intersperse(", ")

    [render_expr(path), " { ", rendered_fields, " }"]
  end

  def render_expr(%Ref{expr: expr, mutable: false}), do: ["&", render_expr(expr)]
  def render_expr(%Ref{expr: expr, mutable: true}), do: ["&mut ", render_expr(expr)]
  def render_expr(%Try{expr: expr}), do: [render_expr(expr), "?"]
  def render_expr(%Tuple{values: values}), do: ["(", render_args(values), ")"]
  def render_expr(%Literal{value: value}) when is_binary(value), do: inspect(value)

  def render_expr(%Literal{value: value}) when is_integer(value) or is_float(value),
    do: to_string(value)

  def render_expr(%Literal{value: true}), do: "true"
  def render_expr(%Literal{value: false}), do: "false"

  def render_expr(%TokenMacro{path: path, tokens: tokens}),
    do: [render_expr(path), "!(", tokens, ")"]

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

  def render_expr(%If{} = if_expr) do
    then_body = if_expr.then |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")
    else_body = if_expr.else |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")

    [
      "if ",
      render_expr(if_expr.condition),
      " {\n",
      indent(then_body),
      "\n} else {\n",
      indent(else_body),
      "\n}"
    ]
  end

  def render_expr(%BinaryOp{left: left, op: op, right: right}) do
    [render_expr(left), " ", render_binary_op(op), " ", render_expr(right)]
  end

  def render_arm(%Arm{pattern: pattern, body: body}) do
    rendered_body = body |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")
    [render_pattern(pattern), " => {\n", indent(rendered_body), "\n},"]
  end

  def render_pattern(%PatVar{name: name}), do: Atom.to_string(name)
  def render_pattern(%PatWildcard{}), do: "_"
  def render_pattern(%PatPath{path: path}), do: render_expr(path)
  def render_pattern(%PatLiteral{value: value}) when is_binary(value), do: inspect(value)
  def render_pattern(%PatLiteral{value: value}) when is_atom(value), do: Atom.to_string(value)
  def render_pattern(%PatNone{}), do: "None"
  def render_pattern(%PatSome{pattern: pattern}), do: ["Some(", render_pattern(pattern), ")"]
  def render_pattern(%PatOk{pattern: pattern}), do: ["Ok(", render_pattern(pattern), ")"]
  def render_pattern(%PatErr{pattern: pattern}), do: ["Err(", render_pattern(pattern), ")"]

  def render_pattern(%PatPathTuple{path: path, patterns: patterns}) do
    [
      render_expr(path),
      "(",
      patterns |> Elixir.Enum.map(&render_pattern/1) |> Elixir.Enum.intersperse(", "),
      ")"
    ]
  end

  def render_pattern(%PatStruct{path: path, fields: fields}) do
    rendered_fields =
      fields
      |> Elixir.Enum.map(fn {name, pattern} ->
        [to_string(name), ": ", render_pattern(pattern)]
      end)
      |> Elixir.Enum.intersperse(", ")

    [render_expr(path), " { ", rendered_fields, " }"]
  end

  def render_pattern(%PatAtomGuard{name: name}),
    do: ["value if value == atoms::", Atom.to_string(name), "()"]

  def render_pattern(%PatTuple{patterns: patterns}) do
    ["(", patterns |> Elixir.Enum.map(&render_pattern/1) |> Elixir.Enum.intersperse(", "), ")"]
  end

  defp render_args(args),
    do: args |> Elixir.Enum.map(&render_expr/1) |> Elixir.Enum.intersperse(", ")

  defp render_binary_op(:eq), do: "=="
  defp render_binary_op(:and), do: "&&"
  defp render_binary_op(:or), do: "||"

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
