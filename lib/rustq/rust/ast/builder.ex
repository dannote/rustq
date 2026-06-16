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

  def use(parts) when is_list(parts), do: %AST.Use{parts: parts}
  def use(tree), do: %AST.Use{tree: tree}

  def module(name, items, opts \\ []),
    do: %AST.Module{name: name, items: flatten(items), vis: Keyword.get(opts, :vis)}

  def const(name, type, expression, opts \\ []),
    do: %AST.Const{name: name, type: type, expr: expr(expression), vis: Keyword.get(opts, :vis)}

  def function_arg(%AST.FunctionArg{} = arg), do: arg
  def function_arg({name, type}), do: %AST.FunctionArg{name: name, type: type}
  def function_arg(name, type), do: %AST.FunctionArg{name: name, type: type}
  def function_args(args), do: Enum.map(args, &function_arg/1)

  def derive(paths), do: %AST.Derive{paths: List.wrap(paths)}

  def macro_item(source), do: %AST.MacroItem{source: source}

  def let(name, expression, opts \\ []),
    do: %AST.Let{pattern: pat(name), expr: expr(expression), type: Keyword.get(opts, :type)}

  def let_mut(name, expression, opts \\ []),
    do: %AST.Let{
      pattern: pat(name),
      expr: expr(expression),
      mutable: true,
      type: Keyword.get(opts, :type)
    }

  def assign(target, expression), do: %AST.Assign{target: expr(target), expr: expr(expression)}
  def stmt(expression), do: %AST.ExprStmt{expr: expr(expression)}
  def return_stmt(expression), do: %AST.Return{expr: expr(expression)}
  def early_return(expression), do: %AST.EarlyReturn{expr: expr(expression)}

  def var(name) when is_atom(name), do: %AST.Var{name: name}
  def path(parts) when is_list(parts), do: %AST.Path{parts: parts}
  def path(part), do: %AST.Path{parts: [part]}
  def path(first, second), do: %AST.Path{parts: [first, second]}
  def path(first, second, third), do: %AST.Path{parts: [first, second, third]}

  def type_path(parts_or_part, opts \\ [])

  def type_path(parts, opts) when is_list(parts),
    do: %AST.TypePath{
      parts: parts,
      lifetimes: Keyword.get(opts, :lifetimes, []),
      generics: Keyword.get(opts, :generics, [])
    }

  def type_path(part, opts) when is_atom(part) or is_binary(part), do: type_path([part], opts)

  def ref(expression), do: %AST.Ref{expr: expr(expression)}
  def mut_ref(expression), do: %AST.Ref{expr: expr(expression), mutable: true}
  def try(expression), do: %AST.Try{expr: expr(expression)}
  def some(expression), do: %AST.Some{expr: expr(expression)}
  def none, do: %AST.None{}
  def ok, do: %AST.Ok{}
  def ok(expression), do: %AST.Ok{expr: expr(expression)}
  def err(expression), do: %AST.Err{expr: expr(expression)}
  def lit(value), do: %AST.Literal{value: value}
  def token_macro(path, tokens), do: %AST.TokenMacro{path: expr_path(path), tokens: tokens}

  def macro_call(path, args \\ []),
    do: %AST.MacroCall{path: expr_path(path), args: Enum.map(args, &expr/1)}

  def vec(values), do: %AST.VecLiteral{values: Enum.map(values, &expr/1)}
  def closure(args, body), do: %AST.Closure{args: args, body: expr(body)}

  def call(name, args \\ []) when is_atom(name),
    do: %AST.LocalCall{name: name, args: Enum.map(List.wrap(args), &expr/1)}

  def path_call(parts, args \\ []) when is_list(parts),
    do: %AST.PathCall{path: %AST.Path{parts: parts}, args: Enum.map(List.wrap(args), &expr/1)}

  def method(receiver, method, args \\ []),
    do: %AST.MethodCall{
      receiver: expr(receiver),
      method: method,
      args: Enum.map(List.wrap(args), &expr/1)
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
  def and_(left, right), do: binary(left, :and, right)
  def or_(left, right), do: binary(left, :or, right)

  def pat(name) when is_atom(name), do: %AST.PatVar{name: name}
  def wildcard, do: %AST.PatWildcard{}
  def path_pat(path), do: %AST.PatPath{path: expr_path(path)}
  def lit_pat(value), do: %AST.PatLiteral{value: value}
  def none_pat, do: %AST.PatNone{}
  def some_pat(pattern), do: %AST.PatSome{pattern: pat_expr(pattern)}
  def ok_pat(pattern), do: %AST.PatOk{pattern: pat_expr(pattern)}
  def err_pat(pattern), do: %AST.PatErr{pattern: pat_expr(pattern)}

  def path_tuple_pat(path, patterns),
    do: %AST.PatPathTuple{path: expr_path(path), patterns: Enum.map(patterns, &pat_expr/1)}

  def struct_pat(path, fields) do
    %AST.PatStruct{
      path: expr_path(path),
      fields: Enum.map(fields, fn {name, pattern} -> {name, pat_expr(pattern)} end)
    }
  end

  def expr(%{__struct__: module} = value)
      when module in [
             AST.Use,
             AST.Module,
             AST.Const,
             AST.MacroItem,
             AST.Var,
             AST.Path,
             AST.Field,
             AST.PathCall,
             AST.MethodCall,
             AST.LocalCall,
             AST.StructLiteral,
             AST.Ref,
             AST.Try,
             AST.Tuple,
             AST.VecLiteral,
             AST.Closure,
             AST.Literal,
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

  def expr_path(%AST.Path{} = path), do: path
  def expr_path(parts) when is_list(parts), do: path(parts)
  def expr_path(part), do: path(part)

  def pat_expr(%{__struct__: module} = value)
      when module in [
             AST.PatVar,
             AST.PatWildcard,
             AST.PatPath,
             AST.PatLiteral,
             AST.PatNone,
             AST.PatSome,
             AST.PatOk,
             AST.PatErr,
             AST.PatPathTuple,
             AST.PatStruct,
             AST.PatTuple
           ],
      do: value

  def pat_expr(name) when is_atom(name), do: pat(name)

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
