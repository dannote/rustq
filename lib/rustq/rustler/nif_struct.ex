defmodule RustQ.Rustler.NifStruct do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3]

  require I

  @spec build(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  def build(name, module, opts \\ []) do
    ast =
      I.struct String.to_atom(to_string(name)),
        vis: Keyword.get(opts, :vis, :pub),
        derive: Keyword.get(opts, :derive, [:Clone, :Debug, :NifStruct]),
        attrs: [
          A.attr_value(:module, module_name(module))
          | normalize_attrs(Keyword.get(opts, :attrs, []))
        ] do
        struct_fields(Keyword.get(opts, :fields, []), Keyword.get(opts, :field_vis, :pub))
      end

    ast
    |> Render.render_item_native()
    |> Rust.item()
  end

  defp struct_fields(fields, default_vis) do
    Enum.map(fields, fn
      %RustQ.Rust.Field{} = rust_field ->
        field(String.to_atom(to_string(rust_field.name)), rust_field.type, vis: rust_field.vis)

      {field_name, type} ->
        field(field_name, type, vis: default_vis)
    end)
  end

  defp normalize_attrs(attrs), do: Enum.map(attrs, &normalize_attr/1)
  defp normalize_attr(%AST.Attribute{} = attr), do: attr

  defp normalize_attr(attr) when is_list(attr),
    do: attr |> IO.iodata_to_binary() |> normalize_attr()

  defp normalize_attr(attr) when is_binary(attr) do
    cond do
      String.contains?(attr, " = ") ->
        [path, value] = String.split(attr, " = ", parts: 2)
        A.attr_value(String.to_atom(path), String.trim(value, ~s|"|))

      String.ends_with?(attr, ")") and String.contains?(attr, "(") ->
        [path, args] = String.split(String.trim_trailing(attr, ")"), "(", parts: 2)

        args =
          args
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.to_atom/1)

        A.attr(String.to_atom(path), args)

      true ->
        A.attr(String.to_atom(attr))
    end
  end

  defp module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp module_name(module) when is_binary(module), do: module
end
