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
          | Static.t()
          | TypeAlias.t()
          | MacroItem.t()
          | MacroItemCall.t()
          | Impl.t()
          | Function.t()
          | Struct.t()
          | Enum.t()

  @type stmt ::
          Let.t()
          | LetElse.t()
          | Assign.t()
          | ExprStmt.t()
          | Return.t()
          | EarlyReturn.t()
          | IfLet.t()
          | For.t()

  @type expr ::
          Var.t()
          | Path.t()
          | Field.t()
          | Index.t()
          | Range.t()
          | Cast.t()
          | UnaryOp.t()
          | PathCall.t()
          | MethodCall.t()
          | StructLiteral.t()
          | LocalCall.t()
          | Ref.t()
          | Try.t()
          | Tuple.t()
          | VecLiteral.t()
          | ArrayLiteral.t()
          | Closure.t()
          | Literal.t()
          | ByteString.t()
          | TokenMacro.t()
          | MacroCall.t()
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

  defnode(Use, :item, [tree: nil, parts: nil, group: nil],
    type:
      quote(
        do: %__MODULE__{
          tree: String.t() | nil,
          parts: [atom() | String.t()] | nil,
          group: {[atom() | String.t()], [atom() | String.t()]} | nil
        }
      )
  )

  defnode(Attribute, :field, [:path, args: [], style: :outer],
    type:
      quote(
        do: %__MODULE__{
          path: [atom() | String.t()],
          args: keyword() | [atom() | String.t()],
          style: :outer | :inner
        }
      )
  )

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

  defnode(Static, :item, [:name, :type, :expr, mutable: false, vis: nil],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          type: RustQ.Rust.AST.type() | String.t(),
          expr: RustQ.Rust.AST.expr(),
          mutable: boolean(),
          vis: RustQ.Rust.AST.vis()
        }
      )
  )

  defnode(TypeAlias, :item, [:name, :type, vis: nil],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          type: RustQ.Rust.AST.type() | String.t(),
          vis: RustQ.Rust.AST.vis()
        }
      )
  )

  defnode(MacroItem, :item, [:source], type: quote(do: %__MODULE__{source: String.t()}))

  defnode(MacroItemCall, :item, [:path, args: []],
    type:
      quote(
        do: %__MODULE__{
          path: RustQ.Rust.AST.Path.t(),
          args: [atom() | String.t() | {atom() | String.t(), String.t()}]
        }
      )
  )

  defnode(Impl, :item, [:target, trait: nil, items: [], attrs: []],
    type:
      quote(
        do: %__MODULE__{
          target: RustQ.Rust.AST.type() | String.t(),
          trait: RustQ.Rust.AST.Path.t() | nil,
          items: [RustQ.Rust.AST.item()],
          attrs: [RustQ.Rust.AST.Attribute.t()]
        }
      )
  )

  defnode(FunctionArg, :field, [:name, :type],
    type: quote(do: %__MODULE__{name: atom(), type: RustQ.Rust.AST.type() | String.t()})
  )

  defnode(
    Function,
    :item,
    [:name, args: [], returns: nil, body: [], lifetime: nil, vis: nil, attrs: []],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          args: [RustQ.Rust.AST.FunctionArg.t()],
          returns: RustQ.Rust.AST.type() | String.t(),
          body: [RustQ.Rust.AST.stmt()],
          lifetime: atom() | nil,
          vis: RustQ.Rust.AST.vis(),
          attrs: [RustQ.Rust.AST.Attribute.t()]
        }
      )
  )

  defnode(Derive, :field, [:paths],
    type: quote(do: %__MODULE__{paths: [[atom() | String.t()] | atom() | String.t()]})
  )

  defnode(Struct, :item, [:name, fields: [], vis: nil, derive: [], lifetime: nil, attrs: []],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          fields: [RustQ.Rust.AST.StructField.t()],
          vis: RustQ.Rust.AST.vis(),
          derive: [RustQ.Rust.AST.Derive.t() | atom()],
          lifetime: atom() | nil,
          attrs: [RustQ.Rust.AST.Attribute.t()]
        }
      )
  )

  defnode(StructField, :field, [:name, :type, vis: nil],
    type:
      quote(do: %__MODULE__{name: atom(), type: RustQ.Rust.AST.type(), vis: RustQ.Rust.AST.vis()})
  )

  defnode(Enum, :item, [:name, variants: [], vis: nil, derive: [], attrs: []],
    type:
      quote(
        do: %__MODULE__{
          name: atom(),
          variants: [RustQ.Rust.AST.EnumVariant.t()],
          vis: RustQ.Rust.AST.vis(),
          derive: [RustQ.Rust.AST.Derive.t() | atom()],
          attrs: [RustQ.Rust.AST.Attribute.t()]
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

  defnode(LetElse, :stmt, [:pattern, :expr, else: []],
    type:
      quote(
        do: %__MODULE__{
          pattern: RustQ.Rust.AST.pat(),
          expr: RustQ.Rust.AST.expr(),
          else: [RustQ.Rust.AST.stmt()]
        }
      )
  )

  defnode(Assign, :stmt, [:target, :expr],
    type: quote(do: %__MODULE__{target: RustQ.Rust.AST.expr(), expr: RustQ.Rust.AST.expr()})
  )

  defnode(ExprStmt, :stmt, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(Return, :stmt, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(EarlyReturn, :stmt, [:expr], type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr()}))

  defnode(IfLet, :stmt, [:pattern, :expr, then: [], else: []],
    type:
      quote(
        do: %__MODULE__{
          pattern: RustQ.Rust.AST.pat(),
          expr: RustQ.Rust.AST.expr(),
          then: [RustQ.Rust.AST.stmt()],
          else: [RustQ.Rust.AST.stmt()]
        }
      )
  )

  defnode(For, :stmt, [:pattern, :expr, body: []],
    type:
      quote(
        do: %__MODULE__{
          pattern: RustQ.Rust.AST.pat(),
          expr: RustQ.Rust.AST.expr(),
          body: [RustQ.Rust.AST.stmt()]
        }
      )
  )

  defnode(Var, :expr, [:name], type: quote(do: %__MODULE__{name: atom()}))

  defnode(Path, :expr, [:parts], type: quote(do: %__MODULE__{parts: [atom() | String.t()]}))

  defnode(Field, :expr, [:receiver, :field],
    type: quote(do: %__MODULE__{receiver: RustQ.Rust.AST.expr(), field: atom() | integer()})
  )

  defnode(Index, :expr, [:receiver, :index],
    type: quote(do: %__MODULE__{receiver: RustQ.Rust.AST.expr(), index: RustQ.Rust.AST.expr()})
  )

  defnode(Range, :expr, [:start, :stop],
    type:
      quote(
        do: %__MODULE__{
          start: RustQ.Rust.AST.expr() | nil,
          stop: RustQ.Rust.AST.expr() | nil
        }
      )
  )

  defnode(Cast, :expr, [:expr, :type],
    type: quote(do: %__MODULE__{expr: RustQ.Rust.AST.expr(), type: RustQ.Rust.AST.type()})
  )

  defnode(UnaryOp, :expr, [:op, :expr],
    type: quote(do: %__MODULE__{op: atom(), expr: RustQ.Rust.AST.expr()})
  )

  defnode(PathCall, :expr, [:path, args: [], generics: []],
    type:
      quote(
        do: %__MODULE__{
          path: RustQ.Rust.AST.Path.t(),
          args: [RustQ.Rust.AST.expr()],
          generics: [RustQ.Rust.AST.type()]
        }
      )
  )

  defnode(MethodCall, :expr, [:receiver, :method, args: [], generics: []],
    type:
      quote(
        do: %__MODULE__{
          receiver: RustQ.Rust.AST.expr(),
          method: atom(),
          args: [RustQ.Rust.AST.expr()],
          generics: [RustQ.Rust.AST.type()]
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

  defnode(VecLiteral, :expr, [:values],
    type: quote(do: %__MODULE__{values: [RustQ.Rust.AST.expr()]})
  )

  defnode(ArrayLiteral, :expr, [:values],
    type: quote(do: %__MODULE__{values: [RustQ.Rust.AST.expr()]})
  )

  defnode(Closure, :expr, [:args, :body],
    type: quote(do: %__MODULE__{args: [atom()], body: RustQ.Rust.AST.expr()})
  )

  defnode(Literal, :expr, [:value],
    type: quote(do: %__MODULE__{value: String.t() | integer() | float() | boolean()})
  )

  defnode(ByteString, :expr, [:value], type: quote(do: %__MODULE__{value: String.t()}))

  defnode(TokenMacro, :expr, [:path, :tokens],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), tokens: String.t()})
  )

  defnode(MacroCall, :expr, [:path, args: []],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), args: [RustQ.Rust.AST.expr()]})
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
          op: :eq | :ne | :lt | :lte | :gt | :gte | :add | :sub | :mul | :div | :and | :or,
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

  defnode(PatAtomGuard, :pat, [:name, module: [:atoms]],
    type: quote(do: %__MODULE__{name: atom(), module: [atom() | String.t()]})
  )

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
      Attribute,
      Module,
      Const,
      Static,
      TypeAlias,
      MacroItem,
      MacroItemCall,
      Impl,
      FunctionArg,
      Function,
      Derive,
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
      LetElse,
      Assign,
      ExprStmt,
      Return,
      EarlyReturn,
      IfLet,
      For,
      Var,
      Path,
      Field,
      Index,
      Range,
      Cast,
      UnaryOp,
      PathCall,
      MethodCall,
      StructLiteral,
      LocalCall,
      Ref,
      Try,
      Tuple,
      VecLiteral,
      ArrayLiteral,
      Closure,
      Literal,
      ByteString,
      TokenMacro,
      MacroCall,
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
  def render_item_native(%Static{} = item), do: render_native(item, &render_static/1)
  def render_item_native(%TypeAlias{} = item), do: render_native(item, &render_type_alias/1)
  def render_item_native(%MacroItem{} = item), do: render_native(item, &render_macro_item/1)

  def render_item_native(%MacroItemCall{} = item),
    do: render_native(item, &render_macro_item_call/1)

  def render_item_native(%Impl{} = item), do: render_native(item, &render_impl/1)
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
    [render_expr(path), "! { ", Elixir.Enum.map_join(args, ", ", &render_macro_arg/1), " }"]
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

  defp render_impl_item(%Function{} = function), do: render_function(function)
  defp render_impl_item(item), do: render_item_native(item)

  def render_function(%Function{} = function) do
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
      function.body |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n") |> indent(),
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_attrs(attrs), do: Elixir.Enum.map(attrs, &[render_attr(&1), "\n"])

  defp render_attr(%Attribute{style: :outer, path: path, args: []}),
    do: ["#[", render_attr_path(path), "]"]

  defp render_attr(%Attribute{style: :outer, path: path, args: args}),
    do: ["#[", render_attr_path(path), "(", render_attr_args(args), ")]"]

  defp render_attr_path(path), do: Elixir.Enum.map_join(path, "::", &to_string/1)

  defp render_attr_args(args) when is_list(args) do
    args
    |> Elixir.Enum.map(&render_attr_arg/1)
    |> Elixir.Enum.intersperse(", ")
  end

  defp render_attr_arg({key, value}), do: [to_string(key), " = ", inspect(value)]
  defp render_attr_arg(value), do: to_string(value)

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
    else_body = stmt.else |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")

    [
      "let ",
      render_pattern(stmt.pattern),
      " = ",
      render_expr(stmt.expr),
      " else {\n",
      indent(else_body),
      "\n};"
    ]
  end

  def render_stmt(%Assign{} = stmt),
    do: [render_expr(stmt.target), " = ", render_expr(stmt.expr), ";"]

  def render_stmt(%ExprStmt{} = stmt), do: [render_expr(stmt.expr), ";"]
  def render_stmt(%Return{} = stmt), do: render_expr(stmt.expr)
  def render_stmt(%EarlyReturn{} = stmt), do: ["return ", render_expr(stmt.expr), ";"]

  def render_stmt(%IfLet{} = stmt) do
    then_body = stmt.then |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")
    else_body = stmt.else |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")
    else_part = if stmt.else == [], do: [], else: [" else {\n", indent(else_body), "\n}"]

    [
      "if let ",
      render_pattern(stmt.pattern),
      " = ",
      render_expr(stmt.expr),
      " {\n",
      indent(then_body),
      "\n}",
      else_part
    ]
  end

  def render_stmt(%For{} = stmt) do
    body = stmt.body |> Elixir.Enum.map(&render_stmt/1) |> Elixir.Enum.join("\n")

    [
      "for ",
      render_pattern(stmt.pattern),
      " in ",
      render_expr(stmt.expr),
      " {\n",
      indent(body),
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
    do: [render_expr(expr), " as ", render_type(type)]

  def render_expr(%UnaryOp{op: op, expr: expr}), do: [render_unary_op(op), render_expr(expr)]

  def render_expr(%PathCall{path: path, args: args, generics: generics}) do
    [render_expr(path), render_generics(generics), "(", render_args(args), ")"]
  end

  def render_expr(%MethodCall{receiver: receiver, method: method, args: args, generics: generics}) do
    [
      render_expr(receiver),
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

  def render_expr(%Literal{value: value}) when is_integer(value) or is_float(value),
    do: to_string(value)

  def render_expr(%Literal{value: true}), do: "true"
  def render_expr(%Literal{value: false}), do: "false"

  def render_expr(%TokenMacro{path: path, tokens: tokens}),
    do: [render_expr(path), "!(", tokens, ")"]

  def render_expr(%MacroCall{path: path, args: args}),
    do: [render_expr(path), "!(", render_args(args), ")"]

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

  defp indent(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Elixir.Enum.map_join("\n", &("    " <> &1))
  end
end
