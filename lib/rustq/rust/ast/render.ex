defmodule RustQ.Rust.AST.Render do
  @moduledoc false

  alias RustQ.Rust.AST.{
    Arm,
    Assign,
    AtomValue,
    Attribute,
    BinaryOp,
    ByteString,
    Cast,
    Closure,
    Const,
    Derive,
    EarlyReturn,
    Enum,
    EnumVariant,
    Err,
    EscapeExpr,
    ExprStmt,
    Field,
    For,
    Function,
    FunctionArg,
    If,
    IfLet,
    Impl,
    Index,
    Let,
    LetElse,
    Literal,
    LocalCall,
    MacroCall,
    MacroItem,
    MacroItemCall,
    Match,
    MethodCall,
    Module,
    NifRaiseAtom,
    None,
    Ok,
    PatAtomGuard,
    PatErr,
    PatLiteral,
    PatNone,
    PatOk,
    PatPath,
    PatPathTuple,
    PatSome,
    PatStruct,
    PatTuple,
    PatVar,
    PatWildcard,
    Path,
    PathCall,
    Range,
    Ref,
    Return,
    Some,
    Static,
    Struct,
    StructField,
    StructLiteral,
    TokenMacro,
    Try,
    Tuple,
    TypeAlias,
    TypeNifResult,
    TypeOption,
    TypePath,
    TypeRef,
    TypeResult,
    TypeUnit,
    TypeVec,
    UnaryOp,
    Use,
    Var,
    VecLiteral,
    ArrayLiteral
  }

  def render_item(%Use{} = item), do: render_native(item, &render_use/1)
  def render_item(%Module{} = item), do: render_native(item, &render_module/1)
  def render_item(%Const{} = item), do: render_native(item, &render_const/1)
  def render_item(%Static{} = item), do: render_native(item, &render_static/1)
  def render_item(%TypeAlias{} = item), do: render_native(item, &render_type_alias/1)
  def render_item(%MacroItem{} = item), do: render_native(item, &render_macro_item/1)

  def render_item(%MacroItemCall{} = item), do: render_macro_item_call(item)

  def render_item(%Impl{} = item), do: render_native(item, &render_impl/1)
  def render_item(%Function{} = item), do: render_native(item, &do_render_function/1)
  def render_item(%Struct{} = item), do: render_native(item, &render_struct/1)
  def render_item(%Enum{} = item), do: render_native(item, &render_enum/1)

  def render_file(items) do
    items
    |> List.wrap()
    |> Elixir.Enum.map_join("\n", &render_item/1)
  end

  def render_function(%Function{} = function), do: render_item(function)

  defp render_native(item, fallback) do
    if Application.get_env(:rustq, :strict_native_ast, false) do
      RustQ.Native.render_ast(item)
    else
      try do
        RustQ.Native.render_ast(item)
      rescue
        _error -> fallback.(item)
      catch
        :exit, _reason -> fallback.(item)
      end
    end
  end

  def render_use(%Use{parts: parts}) when is_list(parts),
    do: ["use ", Elixir.Enum.map_join(parts, "::", &to_string/1), ";"]

  def render_use(%Use{group: {base, names}}) when is_list(base) and is_list(names) do
    [
      "use ",
      Elixir.Enum.map_join(base, "::", &to_string/1),
      "::{",
      names |> Elixir.Enum.map(&render_use_group_member/1) |> Elixir.Enum.intersperse(", "),
      "};"
    ]
  end

  def render_use(%Use{tree: tree}), do: ["use ", tree, ";"]

  def render_module(%Module{} = module) do
    items = module.items |> Elixir.Enum.map(&render_item/1) |> Elixir.Enum.join("\n")

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

  def render_static(%Static{} = static) do
    mutable = if static.mutable, do: "mut ", else: ""

    [
      render_vis(static.vis),
      "static ",
      mutable,
      Atom.to_string(static.name),
      ": ",
      render_type(static.type),
      " = ",
      render_expr(static.expr),
      ";"
    ]
  end

  def render_type_alias(%TypeAlias{} = alias_item) do
    [
      render_vis(alias_item.vis),
      "type ",
      Atom.to_string(alias_item.name),
      " = ",
      render_type(alias_item.type),
      ";"
    ]
  end

  def render_macro_item(%MacroItem{source: source}), do: source

  def render_macro_item_call(%MacroItemCall{path: path, args: args}) do
    [render_expr(path), "! { ", Elixir.Enum.map_join(args, ", ", &render_macro_arg/1), ", }"]
  end

  defp render_macro_arg({name, value}), do: [to_string(name), " = ", inspect(value)]
  defp render_macro_arg(value), do: to_string(value)

  def render_impl(%Impl{} = impl) do
    items = impl.items |> Elixir.Enum.map(&render_impl_item/1) |> Elixir.Enum.join("\n")
    trait = if impl.trait, do: [render_expr(impl.trait), " for "], else: []

    [
      render_attrs(impl.attrs),
      "impl ",
      trait,
      render_type(impl.target),
      " {\n",
      indent(items),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_impl_item(%Function{} = function), do: do_render_function(function)
  defp render_impl_item(item), do: render_item(item)

  defp do_render_function(%Function{} = function) do
    args =
      Elixir.Enum.map_join(function.args, ", ", &render_function_arg/1)

    lifetime = if function.lifetime, do: "<'#{function.lifetime}>", else: ""

    [
      render_attrs(function.attrs),
      render_vis(function.vis),
      "fn ",
      Atom.to_string(function.name),
      lifetime,
      "(",
      args,
      ") -> ",
      render_type(function.returns),
      " {\n",
      render_stmt_block(function.body),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_attrs(attrs), do: Elixir.Enum.map(attrs, &[render_attr(&1), "\n"])

  defp render_attr(%Attribute{style: :outer, path: path, args: []}),
    do: ["#[", render_attr_path(path), "]"]

  defp render_attr(%Attribute{style: :outer, path: path, args: {:value, value}}),
    do: ["#[", render_attr_path(path), " = ", render_attr_value(value), "]"]

  defp render_attr(%Attribute{style: :outer, path: path, args: args}),
    do: ["#[", render_attr_path(path), "(", render_attr_args(args), ")]"]

  defp render_attr_path(path), do: Elixir.Enum.map_join(path, "::", &to_string/1)

  defp render_attr_args(args) when is_list(args) do
    args
    |> Elixir.Enum.map(&render_attr_arg/1)
    |> Elixir.Enum.intersperse(", ")
  end

  defp render_attr_arg({key, value}), do: [to_string(key), " = ", render_attr_value(value)]
  defp render_attr_arg(value), do: to_string(value)
  defp render_attr_value(value) when is_binary(value), do: inspect(value)
  defp render_attr_value(value), do: to_string(value)

  def render_function_arg(%FunctionArg{name: name, type: type}) do
    "#{name}: #{render_type(type)}"
  end

  def render_function_arg({name, type}) do
    "#{name}: #{render_type(type)}"
  end

  def render_struct(%Struct{} = struct) do
    derive = render_derive(struct.derive)
    vis = render_vis(struct.vis)
    lifetime = if struct.lifetime, do: "<'#{struct.lifetime}>", else: ""
    fields = struct.fields |> Elixir.Enum.map(&render_struct_field/1) |> Elixir.Enum.join("\n")

    [
      derive,
      render_attrs(struct.attrs),
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

    [
      derive,
      render_attrs(enum.attrs),
      vis,
      "enum ",
      Atom.to_string(enum.name),
      " {\n",
      variants |> indent(),
      "\n}"
    ]
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
  def render_type(type) when is_atom(type), do: to_string(type)
  def render_type({:raw, source}), do: source
  def render_type({:vec, inner}), do: ["Vec<", render_type(inner), ">"]
  def render_type({:option, inner}), do: ["Option<", render_type(inner), ">"]
  def render_type({:ref, inner}), do: ["&", render_type(inner)]
  def render_type({:mut_ref, inner}), do: ["&mut ", render_type(inner)]
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

  def render_stmt(%LetElse{} = stmt) do
    [
      "let ",
      render_pattern(stmt.pattern),
      " = ",
      render_expr(stmt.expr),
      " else {\n",
      render_stmt_block(stmt.else),
      "\n};"
    ]
  end

  def render_stmt(%Assign{} = stmt),
    do: [render_expr(stmt.target), " = ", render_expr(stmt.expr), ";"]

  def render_stmt(%ExprStmt{} = stmt), do: [render_expr(stmt.expr), ";"]
  def render_stmt(%Return{} = stmt), do: render_expr(stmt.expr)
  def render_stmt(%EarlyReturn{} = stmt), do: ["return ", render_expr(stmt.expr), ";"]

  def render_stmt(%IfLet{} = stmt) do
    else_part =
      if stmt.else == [], do: [], else: [" else {\n", render_stmt_block(stmt.else), "\n}"]

    [
      "if let ",
      render_pattern(stmt.pattern),
      " = ",
      render_expr(stmt.expr),
      " {\n",
      render_stmt_block(stmt.then),
      "\n}",
      else_part
    ]
  end

  def render_stmt(%For{} = stmt) do
    [
      "for ",
      render_pattern(stmt.pattern),
      " in ",
      render_expr(stmt.expr),
      " {\n",
      render_stmt_block(stmt.body),
      "\n}"
    ]
  end

  def render_expr(%Var{name: name}), do: Atom.to_string(name)
  def render_expr(%Path{parts: parts}), do: Elixir.Enum.map_join(parts, "::", &to_string/1)

  def render_expr(%Field{receiver: receiver, field: field}),
    do: [render_expr(receiver), ".", to_string(field)]

  def render_expr(%Index{receiver: receiver, index: index}),
    do: [render_expr(receiver), "[", render_expr(index), "]"]

  def render_expr(%Range{start: start, stop: stop}),
    do: [
      if(start, do: render_expr(start), else: []),
      "..",
      if(stop, do: render_expr(stop), else: [])
    ]

  def render_expr(%Cast{expr: expr, type: type}),
    do: [render_cast_operand(expr), " as ", render_type(type)]

  def render_expr(%UnaryOp{op: op, expr: expr}), do: [render_unary_op(op), render_expr(expr)]

  def render_expr(%PathCall{path: path, args: args, generics: generics}) do
    [render_expr(path), render_generics(generics), "(", render_args(args), ")"]
  end

  def render_expr(%MethodCall{receiver: receiver, method: method, args: args, generics: generics}) do
    [
      render_method_receiver(receiver),
      ".",
      to_string(method),
      render_generics(generics),
      "(",
      render_args(args),
      ")"
    ]
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
  def render_expr(%VecLiteral{values: values}), do: ["vec![", render_args(values), "]"]
  def render_expr(%ArrayLiteral{values: values}), do: ["[", render_args(values), "]"]

  def render_expr(%Closure{args: args, body: body}) do
    ["|", Elixir.Enum.map_join(args, ", ", &to_string/1), "| ", render_expr(body)]
  end

  def render_expr(%Literal{value: value}) when is_binary(value), do: inspect(value)

  def render_expr(%ByteString{value: value}), do: ["b", inspect(value)]

  def render_expr(%EscapeExpr{source: source}), do: source

  def render_expr(%Literal{value: value}) when is_integer(value) or is_float(value),
    do: to_string(value)

  def render_expr(%Literal{value: true}), do: "true"
  def render_expr(%Literal{value: false}), do: "false"

  def render_expr(%TokenMacro{path: path, tokens: tokens}),
    do: [render_expr(path), "!(", tokens, ")"]

  def render_expr(%MacroCall{path: path, args: args}),
    do: [render_expr(path), "!(", render_args(args), ")"]

  def render_expr(%AtomValue{name: name, module: module}) do
    [Elixir.Enum.map_join(module, "::", &to_string/1), "::", Atom.to_string(name), "()"]
  end

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
    [
      "if ",
      render_expr(if_expr.condition),
      " {\n",
      render_stmt_block(if_expr.then),
      "\n} else {\n",
      render_stmt_block(if_expr.else),
      "\n}"
    ]
  end

  def render_expr(%BinaryOp{left: left, op: op, right: right}) do
    [render_expr(left), " ", render_binary_op(op), " ", render_expr(right)]
  end

  def render_arm(%Arm{pattern: pattern, body: body}) do
    [render_pattern(pattern), " => {\n", render_stmt_block(body), "\n},"]
  end

  def render_pattern(%PatVar{name: name, mutable: true}), do: ["mut ", Atom.to_string(name)]
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

  def render_pattern(%PatAtomGuard{name: name, module: module}),
    do: [
      "value if value == ",
      Elixir.Enum.map_join(module, "::", &to_string/1),
      "::",
      Atom.to_string(name),
      "()"
    ]

  def render_pattern(%PatTuple{patterns: patterns}) do
    ["(", patterns |> Elixir.Enum.map(&render_pattern/1) |> Elixir.Enum.intersperse(", "), ")"]
  end

  defp render_args(args),
    do: args |> Elixir.Enum.map(&render_expr/1) |> Elixir.Enum.intersperse(", ")

  defp render_generics([]), do: []

  defp render_generics(generics),
    do: ["::<", generics |> Elixir.Enum.map(&render_type/1) |> Elixir.Enum.intersperse(", "), ">"]

  defp render_binary_op(:eq), do: "=="
  defp render_binary_op(:ne), do: "!="
  defp render_binary_op(:lt), do: "<"
  defp render_binary_op(:lte), do: "<="
  defp render_binary_op(:gt), do: ">"
  defp render_binary_op(:gte), do: ">="
  defp render_binary_op(:add), do: "+"
  defp render_binary_op(:sub), do: "-"
  defp render_binary_op(:mul), do: "*"
  defp render_binary_op(:div), do: "/"
  defp render_binary_op(:and), do: "&&"
  defp render_binary_op(:or), do: "||"

  defp render_method_receiver(%BinaryOp{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_method_receiver(%Cast{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_method_receiver(%Match{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_method_receiver(%If{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_method_receiver(expr), do: render_expr(expr)

  defp render_cast_operand(%BinaryOp{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_cast_operand(%If{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_cast_operand(%Match{} = expr), do: ["(", render_expr(expr), ")"]
  defp render_cast_operand(expr), do: render_expr(expr)

  defp render_use_group_member({base, names}) when is_list(names) do
    [
      to_string(base),
      "::{",
      names |> Elixir.Enum.map(&render_use_group_member/1) |> Elixir.Enum.intersperse(", "),
      "}"
    ]
  end

  defp render_use_group_member(:self), do: "self"
  defp render_use_group_member(:*), do: "*"
  defp render_use_group_member(value), do: to_string(value)

  defp render_unary_op(:not), do: "!"
  defp render_unary_op(:neg), do: "-"
  defp render_unary_op(:deref), do: "*"

  defp render_derive([]), do: []

  defp render_derive(values) do
    [
      "#[derive(",
      values |> Elixir.Enum.flat_map(&derive_paths/1) |> Elixir.Enum.intersperse(", "),
      ")]\n"
    ]
  end

  defp derive_paths(%Derive{paths: paths}), do: Elixir.Enum.map(paths, &derive_path/1)
  defp derive_paths(value), do: [derive_path(value)]

  defp derive_path(parts) when is_list(parts), do: Elixir.Enum.map_join(parts, "::", &to_string/1)
  defp derive_path(value), do: to_string(value)

  defp render_vis(:pub), do: "pub "
  defp render_vis(:crate), do: "pub(crate) "
  defp render_vis(nil), do: []

  defp render_stmt_lines(statements),
    do: statements |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")

  defp render_stmt_block(statements), do: statements |> render_stmt_lines() |> indent()

  defp indent(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Elixir.Enum.map_join("\n", &("    " <> &1))
  end
end
