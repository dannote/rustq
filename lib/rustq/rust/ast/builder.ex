defmodule RustQ.Rust.AST.Builder do
  @moduledoc """
  Small builder DSL for `RustQ.Rust.AST` nodes.

  Use functions for leaves and `do`-block macros for tree-shaped constructs like
  blocks, matches, arms, and returns.
  """

  alias __MODULE__, as: Builder
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.PatternBuilder
  alias RustQ.Rust.AST.TypeBuilder

  alias RustQ.Rust.AST.{
    Arm,
    ArrayLiteral,
    Assign,
    AssignOp,
    AtomValue,
    Attribute,
    BinaryOp,
    BlockExpr,
    Break,
    ByteString,
    Cast,
    Closure,
    Const,
    Continue,
    Derive,
    EarlyReturn,
    Err,
    EscapeExpr,
    ExprStmt,
    Field,
    For,
    FunctionArg,
    If,
    IfLet,
    Impl,
    Index,
    Let,
    LetElse,
    Literal,
    LocalCall,
    Loop,
    MacroCall,
    MacroItem,
    MacroItemCall,
    Match,
    MethodCall,
    Module,
    None,
    Ok,
    Path,
    PathCall,
    Range,
    Ref,
    Return,
    Some,
    Static,
    StructLiteral,
    TokenMacro,
    Try,
    Tuple,
    TypeAlias,
    TypePath,
    UnaryOp,
    Use,
    Var,
    VecLiteral
  }

  defmacro block(do: body) do
    quote do
      Builder.flatten(unquote(block_values(body)))
    end
  end

  defmacro match(expr, do: body) do
    quote do
      %Match{
        expr: Builder.expr(unquote(expr)),
        arms: Builder.flatten(unquote(block_values(body)))
      }
    end
  end

  defmacro arm(pattern, opts \\ [], do: body) do
    quote do
      %Arm{
        pattern: unquote(pattern),
        guard: unquote(opts) |> Keyword.get(:when) |> Builder.maybe_expr(),
        body: Builder.flatten(unquote(block_values(body)))
      }
    end
  end

  defmacro return(do: expression) do
    quote do
      Builder.return_stmt(unquote(expression))
    end
  end

  defmacro return(expression) do
    quote do
      Builder.return_stmt(unquote(expression))
    end
  end

  defmacro if_expr(condition, do: body) do
    {then_body, else_body} = split_if_body(body)

    quote do
      Builder.if_expr(
        unquote(condition),
        Builder.flatten(unquote(block_values(then_body))),
        Builder.flatten(unquote(block_values(else_body)))
      )
    end
  end

  def flatten(values), do: values |> List.wrap() |> List.flatten()

  def use({base, names}) when is_list(base) and is_list(names), do: %Use{group: {base, names}}
  def use(parts) when is_list(parts), do: %Use{parts: parts}
  def use(tree), do: %Use{tree: tree}

  def module(name, items, opts \\ []),
    do: %Module{name: name, items: flatten(items), vis: Keyword.get(opts, :vis)}

  def const(name, type, expression, opts \\ []),
    do: %Const{name: name, type: type, expr: expr(expression), vis: Keyword.get(opts, :vis)}

  def type_alias(name, type, opts \\ []),
    do: %TypeAlias{name: name, type: type, vis: Keyword.get(opts, :vis)}

  def static(name, type, expression, opts \\ []),
    do: %Static{
      name: name,
      type: type,
      expr: expr(expression),
      mutable: Keyword.get(opts, :mutable, false),
      vis: Keyword.get(opts, :vis)
    }

  def function_arg(%FunctionArg{} = arg), do: arg
  def function_arg({name, type}), do: %FunctionArg{name: name, type: type}
  def function_arg(name, type), do: %FunctionArg{name: name, type: type}
  def function_args(args), do: Enum.map(args, &function_arg/1)

  def derive(paths), do: %Derive{paths: List.wrap(paths)}
  def attr(path, args \\ []), do: %Attribute{path: List.wrap(path), args: args}
  def attr_value(path, value), do: %Attribute{path: List.wrap(path), args: {:value, value}}
  def nif_attr(opts \\ []), do: attr([:rustler, :nif], opts)
  def allow_attr(value), do: attr([:allow], List.wrap(value))
  def resource_impl_attr, do: attr([:rustler, :resource_impl])

  def impl(target, opts \\ []) do
    %Impl{
      target: target,
      trait: Keyword.get(opts, :trait) && trait_path(Keyword.fetch!(opts, :trait)),
      items: flatten(Keyword.get(opts, :items, [])),
      attrs: Keyword.get(opts, :attrs, []),
      lifetimes: List.wrap(Keyword.get(opts, :lifetimes, []))
    }
  end

  def macro_item(source), do: %MacroItem{source: source}
  def macro_item_call(path, args \\ []), do: %MacroItemCall{path: expr_path(path), args: args}

  def let(name, expression, opts \\ []),
    do: %Let{pattern: pat(name), expr: expr(expression), type: Keyword.get(opts, :type)}

  def let_mut(name, expression, opts \\ []),
    do: %Let{
      pattern: pat(name),
      expr: expr(expression),
      mutable: true,
      type: Keyword.get(opts, :type)
    }

  def let_else(pattern, expression, else_body),
    do: %LetElse{pattern: pat_expr(pattern), expr: expr(expression), else: flatten(else_body)}

  def assign(target, expression), do: %Assign{target: expr(target), expr: expr(expression)}

  def assign_op(target, op, expression),
    do: %AssignOp{target: expr(target), op: op, expr: expr(expression)}

  def stmt(expression), do: %ExprStmt{expr: expr(expression)}
  def return_stmt(expression), do: %Return{expr: expr(expression)}
  def early_return(expression), do: %EarlyReturn{expr: expr(expression)}

  def if_let(pattern, expression, then_body, opts \\ []) do
    %IfLet{
      pattern: pat_expr(pattern),
      expr: expr(expression),
      then: flatten(then_body),
      else: flatten(Keyword.get(opts, :else, []))
    }
  end

  def for_(pattern, expression, body),
    do: %For{pattern: pat_expr(pattern), expr: expr(expression), body: flatten(body)}

  def block_expr(body), do: %BlockExpr{body: flatten(body)}
  def loop(body), do: %Loop{body: flatten(body)}
  def break, do: %Break{}
  def break(expression), do: %Break{expr: expr(expression)}
  def continue, do: %Continue{}

  def arg(name, type) when is_binary(type), do: %FunctionArg{name: name, type: type}
  def arg(name, type), do: %FunctionArg{name: name, type: type(type)}

  def receiver(opts \\ []),
    do: %FunctionArg{
      name: :self,
      type: nil,
      receiver: true,
      mutable: Keyword.get(opts, :mut, false)
    }

  def type(value), do: TypeBuilder.type(value)

  def var(name) when is_atom(name), do: %Var{name: name}
  def path_parts(parts) when is_list(parts), do: parts
  def path_parts(path) when is_binary(path), do: String.split(path, "::")
  def path_parts(part), do: [part]
  def path(parts) when is_list(parts), do: %Path{parts: parts}
  def path(part) when is_binary(part), do: %Path{parts: path_parts(part)}
  def path(part), do: %Path{parts: [part]}
  def path(first, second), do: %Path{parts: [first, second]}
  def path(first, second, third), do: %Path{parts: [first, second, third]}

  def type_path(parts_or_part, opts \\ []),
    do: TypeBuilder.path(parts_or_part, opts)

  def field(receiver, field), do: %Field{receiver: expr(receiver), field: field}
  def index(receiver, index), do: %Index{receiver: expr(receiver), index: expr(index)}
  def range(start, stop), do: %Range{start: maybe_expr(start), stop: maybe_expr(stop)}
  def cast(expression, type), do: %Cast{expr: expr(expression), type: type}
  def not_(expression), do: %UnaryOp{op: :not, expr: expr(expression)}
  def neg(expression), do: %UnaryOp{op: :neg, expr: expr(expression)}
  def deref(expression), do: %UnaryOp{op: :deref, expr: expr(expression)}
  def byte_string(value), do: %ByteString{value: value}
  def escape_expr(source), do: %EscapeExpr{source: source}
  def path_value(parts), do: path(parts)

  def ref(expression), do: %Ref{expr: expr(expression)}
  def mut_ref(expression), do: %Ref{expr: expr(expression), mutable: true}
  def try(expression), do: %Try{expr: expr(expression)}
  def some(expression), do: %Some{expr: expr(expression)}
  def none, do: %None{}
  def ok, do: %Ok{}
  def ok(expression), do: %Ok{expr: expr(expression)}
  def err(expression), do: %Err{expr: expr(expression)}
  def badarg, do: path([:rustler, :Error, :BadArg])
  def return_badarg, do: return_stmt(err(badarg()))
  def badarg_arm, do: %Arm{pattern: wildcard(), body: [return_badarg()]}
  def lit(value), do: %Literal{value: value}
  def token_macro(path, tokens), do: %TokenMacro{path: expr_path(path), tokens: tokens}

  def atom(name, opts \\ []),
    do: %AtomValue{name: name, module: Keyword.get(opts, :module, [:atoms])}

  def macro_call(path, args \\ []),
    do: %MacroCall{path: expr_path(path), args: Enum.map(args, &expr/1)}

  def tuple(values), do: %Tuple{values: Enum.map(values, &expr/1)}
  def vec(values), do: %VecLiteral{values: Enum.map(values, &expr/1)}
  def array(values), do: %ArrayLiteral{values: Enum.map(values, &expr/1)}
  def slice(values), do: ref(array(values))
  def closure(args, body), do: %Closure{args: args, body: expr(body)}

  def call(name, args \\ []) when is_atom(name) do
    if name |> Atom.to_string() |> String.ends_with?("!") do
      RustQ.Atom.identifier!(String.trim_trailing(Atom.to_string(name), "!"))
      |> macro_call(args)
    else
      %LocalCall{name: name, args: Enum.map(List.wrap(args), &expr/1)}
    end
  end

  def path_call(parts, args \\ [], opts \\ []) when is_list(parts),
    do: %PathCall{
      path: %Path{parts: parts},
      args: Enum.map(List.wrap(args), &expr/1),
      generics: Keyword.get(opts, :generics, [])
    }

  def method(receiver, method, args \\ [], opts \\ []),
    do: %MethodCall{
      receiver: expr(receiver),
      method: method,
      args: Enum.map(List.wrap(args), &expr/1),
      generics: Keyword.get(opts, :generics, [])
    }

  def struct(path, fields) do
    %StructLiteral{
      path: expr_path(path),
      fields: Enum.map(fields, fn {name, expression} -> {name, expr(expression)} end)
    }
  end

  def match_expr(expression, arms), do: %Match{expr: expr(expression), arms: flatten(arms)}

  def if_expr(condition, then_body, else_body),
    do: %If{condition: expr(condition), then: flatten(then_body), else: flatten(else_body)}

  def binary(left, op, right), do: %BinaryOp{left: expr(left), op: op, right: expr(right)}
  def eq(left, right), do: binary(left, :eq, right)
  def ne(left, right), do: binary(left, :ne, right)
  def lt(left, right), do: binary(left, :lt, right)
  def lte(left, right), do: binary(left, :lte, right)
  def gt(left, right), do: binary(left, :gt, right)
  def gte(left, right), do: binary(left, :gte, right)
  def add(left, right), do: binary(left, :add, right)
  def sub(left, right), do: binary(left, :sub, right)
  def mul(left, right), do: binary(left, :mul, right)
  def div(left, right), do: binary(left, :div, right)
  def and_(left, right), do: binary(left, :and, right)
  def or_(left, right), do: binary(left, :or, right)

  def pat(name) when is_atom(name), do: PatternBuilder.var(name)
  def wildcard, do: PatternBuilder.wildcard()

  def expr(%{__struct__: module} = value)
      when module in [
             Use,
             AST.Attribute,
             AST.Module,
             AST.Const,
             AST.Static,
             AST.TypeAlias,
             AST.MacroItem,
             AST.MacroItemCall,
             AST.Impl,
             AST.Var,
             AST.Path,
             AST.Field,
             AST.Index,
             AST.Range,
             AST.Cast,
             AST.UnaryOp,
             AST.PathCall,
             AST.MethodCall,
             AST.LocalCall,
             AST.StructLiteral,
             AST.Ref,
             AST.Try,
             AST.Tuple,
             AST.VecLiteral,
             AST.ArrayLiteral,
             AST.Closure,
             AST.Literal,
             AST.ByteString,
             AST.EscapeExpr,
             AST.TokenMacro,
             AST.MacroCall,
             AST.AtomValue,
             AST.None,
             AST.Some,
             AST.Ok,
             AST.Err,
             AST.NifRaiseAtom,
             AST.BlockExpr,
             AST.Match,
             AST.If,
             AST.BinaryOp
           ],
      do: value

  def expr(name) when is_atom(name), do: var(name)

  def expr(value)
      when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value),
      do: lit(value)

  def maybe_expr(nil), do: nil
  def maybe_expr(value), do: expr(value)

  def trait_path(%TypePath{} = path), do: path
  def trait_path(path) when is_binary(path), do: type_path(path)
  def trait_path(parts) when is_list(parts), do: type_path(parts)
  def trait_path(part), do: type_path(part)

  def expr_path(%Path{} = path), do: path
  def expr_path(parts) when is_list(parts), do: path(parts)
  def expr_path(part), do: path(part)

  def pat_expr(value), do: PatternBuilder.pattern(value)

  defp block_values({:__block__, _meta, expressions}) do
    quote do
      [unquote_splicing(expressions)]
    end
  end

  defp block_values(expression) do
    quote do
      [unquote(expression)]
    end
  end

  defp split_if_body({:__block__, _meta, expressions}) do
    case Enum.split_while(expressions, fn
           {:else, _, _} -> false
           _other -> true
         end) do
      {then_body, [{:else, _, [[do: else_body]]}]} -> {block_ast(then_body), else_body}
      {then_body, [{:else, _, [else_body]}]} -> {block_ast(then_body), else_body}
      {then_body, []} -> {block_ast(then_body), nil}
    end
  end

  defp split_if_body(expression), do: {expression, nil}

  defp block_ast([expression]), do: expression
  defp block_ast(expressions), do: {:__block__, [], expressions}
end
