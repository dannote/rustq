defmodule RustQ.Rust.AST.ItemBuilder do
  @moduledoc false

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  def field(name, type, opts \\ []),
    do: %AST.StructField{name: name, type: type, vis: Keyword.get(opts, :vis)}

  def const(name, type, expression, opts \\ []), do: A.const(name, type, expression, opts)
  def static(name, type, expression, opts \\ []), do: A.static(name, type, expression, opts)
  def type_alias(name, type, opts \\ []), do: A.type_alias(name, type, opts)

  @doc false
  defmacro struct(name, opts \\ [], do: body) do
    quote do
      %AST.Struct{
        name: unquote(name),
        vis: Keyword.get(unquote(opts), :vis),
        lifetime: Keyword.get(unquote(opts), :lifetime),
        derive: Keyword.get(unquote(opts), :derive, []),
        attrs: Keyword.get(unquote(opts), :attrs, []),
        fields: A.flatten(unquote(block_values(body)))
      }
    end
  end

  @doc false
  defmacro impl(target, opts \\ [], do: body) do
    quote do
      %AST.Impl{
        target: unquote(target),
        trait:
          Keyword.get(unquote(opts), :trait) && A.expr_path(Keyword.fetch!(unquote(opts), :trait)),
        attrs: Keyword.get(unquote(opts), :attrs, []),
        items: A.flatten(unquote(block_values(body)))
      }
    end
  end

  @doc false
  defmacro function(name, opts \\ [], do: body) do
    quote do
      %AST.Function{
        name: unquote(name),
        vis: Keyword.get(unquote(opts), :vis),
        args: A.function_args(Keyword.get(unquote(opts), :args, [])),
        returns: Keyword.fetch!(unquote(opts), :returns),
        lifetime: Keyword.get(unquote(opts), :lifetime),
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
