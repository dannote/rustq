defmodule RustQ.Rust do
  @moduledoc """
  Rendering boundary for structural RustQ AST and explicit Rust fragments.

  Build generated Rust with `RustQ.Rust.AST.Builder`, `ItemBuilder`,
  `PatternBuilder`, and `TypeBuilder`. Keep those values structural until they
  are passed to a RustQ template or explicitly rendered here.

  Use `fragment/2` only for small Rust syntax escapes that RustQ cannot yet
  represent as AST.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render
  alias RustQ.Rust.AST.TypeBuilder
  alias RustQ.Rust.Fragment

  @doc "Builds an explicit Rust source fragment for a known splice context."
  @spec fragment(Fragment.kind(), iodata()) :: Fragment.t()
  def fragment(kind, source), do: %Fragment{kind: kind, source: source}

  @doc "Renders one Rust AST item, struct field, or explicit fragment."
  @spec render(AST.item() | AST.StructField.t() | Fragment.t() | iodata()) :: String.t()
  def render(value), do: to_fragment(value)

  @doc "Renders a list of Rust items separated by blank lines."
  @spec render_all([AST.item() | Fragment.t()]) :: String.t()
  def render_all(items), do: Enum.map_join(items, "\n\n", &to_fragment/1)

  @doc "Renders a structural Rust type."
  @spec render_type(AST.type() | atom() | String.t() | tuple() | [term()]) :: String.t()
  def render_type(type) do
    type
    |> TypeBuilder.type()
    |> Render.render_type()
    |> IO.iodata_to_binary()
  end

  @doc false
  def to_fragment(%Fragment{source: source}), do: IO.iodata_to_binary(source)

  def to_fragment(%AST.StructField{} = field),
    do: render_with(&Render.render_struct_field/1, field)

  def to_fragment(%AST.Arm{} = arm), do: render_with(&Render.render_arm/1, arm)

  def to_fragment(%{__struct__: module} = node) do
    category =
      if Code.ensure_loaded?(module) and function_exported?(module, :__rustq_ast_category__, 0),
        do: module.__rustq_ast_category__()

    case category do
      :item -> render_with(&Render.render_item/1, node)
      :stmt -> render_with(&Render.render_stmt/1, node)
      :expr -> render_with(&Render.render_expr/1, node)
      :pat -> render_with(&Render.render_pattern/1, node)
      :type -> render_with(&Render.render_type/1, node)
      _other -> raise ArgumentError, "expected a renderable RustQ AST node, got: #{inspect(node)}"
    end
  end

  def to_fragment(value) when is_binary(value), do: value
  def to_fragment(value) when is_list(value), do: IO.iodata_to_binary(value)

  @doc false
  @spec literal(term()) :: String.t()
  def literal(value) when is_binary(value), do: inspect(value)
  def literal(value) when is_boolean(value), do: to_string(value)
  def literal(nil), do: "None"
  def literal(value) when is_integer(value) or is_float(value), do: to_string(value)

  defp render_with(renderer, node), do: node |> renderer.() |> IO.iodata_to_binary()
end
