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
          | EscapeExpr.t()
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
          args: keyword() | [atom() | String.t()] | {:value, String.t() | atom()},
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

  defnode(EscapeExpr, :expr, [:source], type: quote(do: %__MODULE__{source: String.t()}))

  defnode(TokenMacro, :expr, [:path, :tokens],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), tokens: String.t()})
  )

  defnode(MacroCall, :expr, [:path, args: []],
    type: quote(do: %__MODULE__{path: RustQ.Rust.AST.Path.t(), args: [RustQ.Rust.AST.expr()]})
  )

  defnode(AtomValue, :expr, [:name, module: [:atoms]],
    type: quote(do: %__MODULE__{name: atom(), module: [atom() | String.t()]})
  )

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

  defnode(PatVar, :pat, [:name, mutable: false],
    type: quote(do: %__MODULE__{name: atom(), mutable: boolean()})
  )

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

  def type_node?(term), do: category_node?(term, :type)
  def expr_node?(term), do: category_node?(term, :expr)
  def pat_node?(term), do: category_node?(term, :pat)

  defp category_node?(%{__struct__: module}, category) do
    Code.ensure_loaded?(module) and function_exported?(module, :__rustq_ast_category__, 0) and
      module.__rustq_ast_category__() == category
  end

  defp category_node?(_term, _category), do: false

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
      EscapeExpr,
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
end
