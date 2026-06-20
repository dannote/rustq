defmodule RustQ.Meta.Attrs do
  @moduledoc """
  Collects Rust-facing attributes declared around `defrust` definitions.
  """

  alias RustQ.Rust.AST

  def take_pending(module) do
    nif = Module.get_attribute(module, :nif)
    allow = Module.get_attribute(module, :allow) |> List.wrap() |> Enum.reverse()
    Module.delete_attribute(module, :nif)
    Module.delete_attribute(module, :allow)

    []
    |> add_nif_attr(nif)
    |> Kernel.++(Enum.map(allow, &allow_attr/1))
  end

  def current_rust_mod(module), do: Module.get_attribute(module, :rustq_current_rust_mod)

  defp add_nif_attr(attrs, nil), do: attrs
  defp add_nif_attr(attrs, false), do: attrs
  defp add_nif_attr(attrs, true), do: attrs ++ [%AST.Attribute{path: [:rustler, :nif]}]

  defp add_nif_attr(attrs, opts) when is_list(opts),
    do: attrs ++ [%AST.Attribute{path: [:rustler, :nif], args: opts}]

  defp allow_attr(values), do: %AST.Attribute{path: [:allow], args: List.wrap(values)}
end
