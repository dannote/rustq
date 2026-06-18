defmodule RustQ.Rust.AST.Builder do
  @moduledoc """
  Small builder DSL for `RustQ.Rust.AST` nodes.

  Use functions for leaves and `do`-block macros for tree-shaped constructs like
  blocks, matches, arms, and returns.
  """

  alias RustQ.Rust.AST

  defmacro block(do: body) do
    quote do
      RustQ.Rust.AST.Builder.flatten(unquote(block_values(body)))
    end
  end

  defmacro match(expr, do: body) do
    quote do
      %AST.Match{
        expr: RustQ.Rust.AST.Builder.expr(unquote(expr)),
        arms: RustQ.Rust.AST.Builder.flatten(unquote(block_values(body)))
      }
    end
  end

  defmacro arm(pattern, do: body) do
    quote do
      %AST.Arm{
        pattern: unquote(pattern),
        body: RustQ.Rust.AST.Builder.flatten(unquote(block_values(body)))
      }
    end
  end

  defmacro return(do: expression) do
    quote do
      RustQ.Rust.AST.Builder.return_stmt(unquote(expression))
    end
  end

  defmacro return(expression) do
    quote do
      RustQ.Rust.AST.Builder.return_stmt(unquote(expression))
    end
  end

  defmacro if_expr(condition, do: body) do
    {then_body, else_body} = split_if_body(body)

    quote do
      RustQ.Rust.AST.Builder.if_expr(
        unquote(condition),
        RustQ.Rust.AST.Builder.flatten(unquote(block_values(then_body))),
        RustQ.Rust.AST.Builder.flatten(unquote(block_values(else_body)))
      )
    end
  end

  def flatten(values), do: values |> List.wrap() |> List.flatten()

  def use({base, names}) when is_list(base) and is_list(names), do: %AST.Use{group: {base, names}}
  def use(parts) when is_list(parts), do: %AST.Use{parts: parts}
  def use(tree), do: %AST.Use{tree: tree}

  def module(name, items, opts \\ []),
    do: %AST.Module{name: name, items: flatten(items), vis: Keyword.get(opts, :vis)}

  def const(name, type, expression, opts \\ []),
    do: %AST.Const{name: name, type: type, expr: expr(expression), vis: Keyword.get(opts, :vis)}

  def type_alias(name, type, opts \\ []),
    do: %AST.TypeAlias{name: name, type: type, vis: Keyword.get(opts, :vis)}

  def static(name, type, expression, opts \\ []),
    do: %AST.Static{
      name: name,
      type: type,
      expr: expr(expression),
      mutable: Keyword.get(opts, :mutable, false),
      vis: Keyword.get(opts, :vis)
    }

  def function_arg(%AST.FunctionArg{} = arg), do: arg
  def function_arg({name, type}), do: %AST.FunctionArg{name: name, type: type}
  def function_arg(name, type), do: %AST.FunctionArg{name: name, type: type}
  def function_args(args), do: Enum.map(args, &function_arg/1)

  def derive(paths), do: %AST.Derive{paths: List.wrap(paths)}
  def attr(path, args \\ []), do: %AST.Attribute{path: List.wrap(path), args: args}
  def attr_value(path, value), do: %AST.Attribute{path: List.wrap(path), args: {:value, value}}
  def nif_attr(opts \\ []), do: attr([:rustler, :nif], opts)
  def allow_attr(value), do: attr([:allow], List.wrap(value))
  def resource_impl_attr, do: attr([:rustler, :resource_impl])

  def impl(target, opts \\ []) do
    %AST.Impl{
      target: target,
      trait: Keyword.get(opts, :trait) && expr_path(Keyword.fetch!(opts, :trait)),
      items: flatten(Keyword.get(opts, :items, [])),
      attrs: Keyword.get(opts, :attrs, [])
    }
  end

  def macro_item(source), do: %AST.MacroItem{source: source}
  def macro_item_call(path, args \\ []), do: %AST.MacroItemCall{path: expr_path(path), args: args}

  def let(name, expression, opts \\ []),
    do: %AST.Let{pattern: pat(name), expr: expr(expression), type: Keyword.get(opts, :type)}

  def let_mut(name, expression, opts \\ []),
    do: %AST.Let{
      pattern: pat(name),
      expr: expr(expression),
      mutable: true,
      type: Keyword.get(opts, :type)
    }

  def let_else(pattern, expression, else_body),
    do: %AST.LetElse{pattern: pat_expr(pattern), expr: expr(expression), else: flatten(else_body)}

  def assign(target, expression), do: %AST.Assign{target: expr(target), expr: expr(expression)}
  def stmt(expression), do: %AST.ExprStmt{expr: expr(expression)}
  def return_stmt(expression), do: %AST.Return{expr: expr(expression)}
  def early_return(expression), do: %AST.EarlyReturn{expr: expr(expression)}

  def if_let(pattern, expression, then_body, opts \\ []) do
    %AST.IfLet{
      pattern: pat_expr(pattern),
      expr: expr(expression),
      then: flatten(then_body),
      else: flatten(Keyword.get(opts, :else, []))
    }
  end

  def for_(pattern, expression, body),
    do: %AST.For{pattern: pat_expr(pattern), expr: expr(expression), body: flatten(body)}

  def arg(name, type) when is_binary(type), do: %AST.FunctionArg{name: name, type: type}
  def arg(name, type), do: %AST.FunctionArg{name: name, type: type(type)}

  def type(value), do: RustQ.Rust.AST.TypeBuilder.type(value)

  def var(name) when is_atom(name), do: %AST.Var{name: name}
  def path(parts) when is_list(parts), do: %AST.Path{parts: parts}
  def path(part), do: %AST.Path{parts: [part]}
  def path(first, second), do: %AST.Path{parts: [first, second]}
  def path(first, second, third), do: %AST.Path{parts: [first, second, third]}

  def type_path(parts_or_part, opts \\ []),
    do: RustQ.Rust.AST.TypeBuilder.path(parts_or_part, opts)

  def field(receiver, field), do: %AST.Field{receiver: expr(receiver), field: field}
  def index(receiver, index), do: %AST.Index{receiver: expr(receiver), index: expr(index)}
  def range(start, stop), do: %AST.Range{start: maybe_expr(start), stop: maybe_expr(stop)}
  def cast(expression, type), do: %AST.Cast{expr: expr(expression), type: type}
  def not_(expression), do: %AST.UnaryOp{op: :not, expr: expr(expression)}
  def neg(expression), do: %AST.UnaryOp{op: :neg, expr: expr(expression)}
  def deref(expression), do: %AST.UnaryOp{op: :deref, expr: expr(expression)}
  def byte_string(value), do: %AST.ByteString{value: value}
  def escape_expr(source), do: %AST.EscapeExpr{source: source}
  def path_value(parts), do: path(parts)

  def ref(expression), do: %AST.Ref{expr: expr(expression)}
  def mut_ref(expression), do: %AST.Ref{expr: expr(expression), mutable: true}
  def try(expression), do: %AST.Try{expr: expr(expression)}
  def some(expression), do: %AST.Some{expr: expr(expression)}
  def none, do: %AST.None{}
  def ok, do: %AST.Ok{}
  def ok(expression), do: %AST.Ok{expr: expr(expression)}
  def err(expression), do: %AST.Err{expr: expr(expression)}
  def badarg, do: path([:rustler, :Error, :BadArg])
  def return_badarg, do: return_stmt(err(badarg()))
  def badarg_arm, do: %AST.Arm{pattern: wildcard(), body: [return_badarg()]}
  def lit(value), do: %AST.Literal{value: value}
  def token_macro(path, tokens), do: %AST.TokenMacro{path: expr_path(path), tokens: tokens}

  def atom(name, opts \\ []),
    do: %AST.AtomValue{name: name, module: Keyword.get(opts, :module, [:atoms])}

  def macro_call(path, args \\ []),
    do: %AST.MacroCall{path: expr_path(path), args: Enum.map(args, &expr/1)}

  def tuple(values), do: %AST.Tuple{values: Enum.map(values, &expr/1)}
  def vec(values), do: %AST.VecLiteral{values: Enum.map(values, &expr/1)}
  def array(values), do: %AST.ArrayLiteral{values: Enum.map(values, &expr/1)}
  def slice(values), do: ref(array(values))
  def closure(args, body), do: %AST.Closure{args: args, body: expr(body)}

  def call(name, args \\ []) when is_atom(name) do
    if name |> Atom.to_string() |> String.ends_with?("!") do
      name
      |> Atom.to_string()
      |> String.trim_trailing("!")
      |> String.to_atom()
      |> macro_call(args)
    else
      %AST.LocalCall{name: name, args: Enum.map(List.wrap(args), &expr/1)}
    end
  end

  def path_call(parts, args \\ [], opts \\ []) when is_list(parts),
    do: %AST.PathCall{
      path: %AST.Path{parts: parts},
      args: Enum.map(List.wrap(args), &expr/1),
      generics: Keyword.get(opts, :generics, [])
    }

  def method(receiver, method, args \\ [], opts \\ []),
    do: %AST.MethodCall{
      receiver: expr(receiver),
      method: method,
      args: Enum.map(List.wrap(args), &expr/1),
      generics: Keyword.get(opts, :generics, [])
    }

  def struct(path, fields) do
    %AST.StructLiteral{
      path: expr_path(path),
      fields: Enum.map(fields, fn {name, expression} -> {name, expr(expression)} end)
    }
  end

  def match_expr(expression, arms), do: %AST.Match{expr: expr(expression), arms: flatten(arms)}

  def if_expr(condition, then_body, else_body),
    do: %AST.If{condition: expr(condition), then: flatten(then_body), else: flatten(else_body)}

  def binary(left, op, right), do: %AST.BinaryOp{left: expr(left), op: op, right: expr(right)}
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

  def pat(name) when is_atom(name), do: RustQ.Rust.AST.PatternBuilder.var(name)
  def wildcard, do: RustQ.Rust.AST.PatternBuilder.wildcard()

  def expr(%{__struct__: module} = value)
      when module in [
             AST.Use,
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
             AST.Match,
             AST.If,
             AST.BinaryOp
           ],
      do: value

  def expr(name) when is_atom(name), do: var(name)

  def expr(value)
      when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value),
      do: lit(value)

  defp maybe_expr(nil), do: nil
  defp maybe_expr(value), do: expr(value)

  def expr_path(%AST.Path{} = path), do: path
  def expr_path(parts) when is_list(parts), do: path(parts)
  def expr_path(part), do: path(part)

  def pat_expr(value), do: RustQ.Rust.AST.PatternBuilder.pattern(value)

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
