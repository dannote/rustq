defmodule RustQ.Rust.AST.ItemBuilder do
  @moduledoc false

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  @doc false
  defmacro function(name, opts \\ [], do: body) do
    quote do
      %AST.Function{
        name: unquote(name),
        vis: Keyword.get(unquote(opts), :vis),
        args: Keyword.get(unquote(opts), :args, []),
        returns: Keyword.fetch!(unquote(opts), :returns),
        lifetime: Keyword.get(unquote(opts), :lifetime),
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
