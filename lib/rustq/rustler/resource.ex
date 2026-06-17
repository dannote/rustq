defmodule RustQ.Rustler.Resource do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3, function: 3, impl: 3]

  require A
  require I

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts \\ []) do
    struct_item = resource_struct_ast(name, Keyword.get(opts, :fields, []))
    impl_item = resource_impl_ast(name)

    [
      Rust.item(Render.render_item_native(struct_item)),
      Rust.item(Render.render_item_native(impl_item))
    ]
  end

  defp resource_struct_ast(name, fields) do
    I.struct String.to_atom(to_string(name)) do
      Enum.map(fields, fn {field_name, type} -> field(field_name, type, vis: :pub) end)
    end
  end

  defp resource_impl_ast(name) do
    impl A.type_path(name), trait: [:rustler, :Resource], attrs: [A.resource_impl_attr()] do
      []
    end
  end

  @spec type_alias(atom() | String.t(), keyword()) :: Rust.TypeAlias.t()
  def type_alias(name, opts \\ []) do
    alias_name = Keyword.get(opts, :as, "#{name}Resource")

    Rust.type_alias(alias_name, {:raw, Rust.type(:ResourceArc, [name])},
      vis: Keyword.get(opts, :vis)
    )
  end

  @spec arc(atom() | String.t()) :: String.t()
  def arc(name), do: Rust.type(:ResourceArc, [name])

  @spec handle(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def handle(name, opts \\ []) do
    build(name, opts) ++ [handle_decode(name, opts)]
  end

  @spec decode(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def decode(name, opts \\ []) do
    function_name = Keyword.get(opts, :fn, "decode_#{Macro.underscore(to_string(name))}_resource")

    Rust.item(Render.render_item_native(resource_decode_ast(name, function_name)))
  end

  @spec handle_decode(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def handle_decode(name, opts \\ []) do
    function_name =
      Keyword.get(opts, :decoder, "decode_#{Macro.underscore(to_string(name))}_handle")

    field = Keyword.get(opts, :handle_field, "ref")

    Rust.item(Render.render_item_native(resource_handle_decode_ast(name, function_name, field)))
  end

  defp resource_decode_ast(name, function_name) do
    resource_type = resource_arc_type(name)

    function String.to_atom(to_string(function_name)),
      lifetime: :a,
      args: [term: A.type_path(:Term, lifetimes: [:a])],
      returns: %AST.TypeNifResult{inner: resource_type} do
      A.return(A.method(:term, :decode, [], generics: [resource_type]))
    end
  end

  defp resource_handle_decode_ast(name, function_name, field) do
    resource_type = resource_arc_type(name)

    function String.to_atom(to_string(function_name)),
      lifetime: :a,
      args: [term: A.type_path(:Term, lifetimes: [:a])],
      returns: %AST.TypeNifResult{inner: resource_type} do
      A.return(
        A.method(
          A.try(
            A.method(:term, :map_get, [
              A.try(
                A.path_call([:Atom, :from_bytes], [
                  A.method(:term, :get_env),
                  A.byte_string(field_to_string(field))
                ])
              )
            ])
          ),
          :decode,
          [],
          generics: [resource_type]
        )
      )
    end
  end

  defp resource_arc_type(name), do: A.type_path(:ResourceArc, generics: [A.type_path(name)])

  defp field_to_string(field) when is_atom(field), do: Atom.to_string(field)
  defp field_to_string(field) when is_binary(field), do: field

  @spec init(atom() | String.t()) :: Rust.Fragment.t()
  def init(name) do
    Rust.item("rustler::resource!(#{name}, env);")
  end
end
