defmodule RustQ.Rustler.NifStruct do
  @moduledoc false

  alias RustQ.Rust

  @spec build(atom() | String.t(), module() | String.t(), keyword()) :: Rust.Fragment.t()
  def build(name, module, opts \\ []) do
    fields =
      opts
      |> Keyword.get(:fields, [])
      |> Enum.map(fn
        %RustQ.Rust.Field{} = field -> field
        {field, type} -> Rust.field(field, type, vis: Keyword.get(opts, :field_vis, :pub))
      end)

    name
    |> Rust.struct(
      vis: Keyword.get(opts, :vis, :pub),
      derive: Keyword.get(opts, :derive, [:Clone, :Debug, :NifStruct]),
      fields: fields,
      attrs: [["module = ", inspect(module_name(module))]] ++ Keyword.get(opts, :attrs, [])
    )
    |> Rust.to_fragment()
    |> Rust.item()
  end

  defp module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp module_name(module) when is_binary(module), do: module
end
