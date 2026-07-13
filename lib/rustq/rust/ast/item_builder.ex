defmodule RustQ.Rust.AST.ItemBuilder do
  @moduledoc """
  Constructors for Rust item declarations with Elixir block syntax.

  Use this module for declarations whose children read naturally as a block:
  `struct/3`, `impl/3`, and `function/3`. `RustQ.Rust.AST.Builder` covers
  expressions, statements, and simpler items.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.Identifier

  def field(name, type, opts \\ []),
    do: %AST.StructField{
      name: Identifier.atom!(to_string(name)),
      type: type,
      vis: Keyword.get(opts, :vis)
    }

  def const(name, type, expression, opts \\ []), do: A.const(name, type, expression, opts)
  def static(name, type, expression, opts \\ []), do: A.static(name, type, expression, opts)
  def type_alias(name, type, opts \\ []), do: A.type_alias(name, type, opts)

  @doc "Builds a Rust struct declaration from structural fields."
  defmacro struct(name, opts \\ [], do: body) do
    quote do
      %AST.Struct{
        name: Identifier.atom!(to_string(unquote(name))),
        vis: Keyword.get(unquote(opts), :vis),
        lifetime: Keyword.get(unquote(opts), :lifetime),
        derive: Keyword.get(unquote(opts), :derive, []),
        attrs: Keyword.get(unquote(opts), :attrs, []),
        fields: A.flatten(unquote(block_values(body)))
      }
    end
  end

  @doc "Builds a Rust impl declaration from structural items."
  defmacro impl(target, opts \\ [], do: body) do
    quote do
      %AST.Impl{
        target: unquote(target),
        trait:
          Keyword.get(unquote(opts), :trait) &&
            A.trait_path(Keyword.fetch!(unquote(opts), :trait)),
        attrs: Keyword.get(unquote(opts), :attrs, []),
        lifetimes: List.wrap(Keyword.get(unquote(opts), :lifetimes, [])),
        items: A.flatten(unquote(block_values(body)))
      }
    end
  end

  @doc "Builds a Rust function item from structural arguments and statements."
  defmacro function(name, opts \\ [], do: body) do
    quote do
      %AST.Function{
        name: Identifier.atom!(to_string(unquote(name))),
        vis: Keyword.get(unquote(opts), :vis),
        args: A.function_args(Keyword.get(unquote(opts), :args, [])),
        returns: Keyword.fetch!(unquote(opts), :returns),
        lifetimes: List.wrap(Keyword.get(unquote(opts), :lifetimes, [])),
        attrs: Keyword.get(unquote(opts), :attrs, []),
        body: A.flatten(unquote(block_values(body)))
      }
    end
  end

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
end
