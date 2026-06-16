defmodule RustQ.Rustler.Resource do
  @moduledoc false

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  import RustQ.Rust.AST.ItemBuilder

  require A
  require RustQ.Rust.AST.ItemBuilder

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts \\ []) do
    struct = %AST.Struct{
      name: String.to_atom(to_string(name)),
      fields:
        opts
        |> Keyword.get(:fields, [])
        |> Enum.map(fn {field, type} -> %AST.StructField{name: field, type: type, vis: :pub} end)
    }

    impl = %AST.Impl{
      target: A.type_path(name),
      trait: A.path([:rustler, :Resource]),
      attrs: [A.resource_impl_attr()]
    }

    [Rust.item(AST.render_item_native(struct)), Rust.item(AST.render_item_native(impl))]
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

    Rust.item(AST.render_item_native(resource_decode_ast(name, function_name)))
  end

  @spec handle_decode(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def handle_decode(name, opts \\ []) do
    function_name =
      Keyword.get(opts, :decoder, "decode_#{Macro.underscore(to_string(name))}_handle")

    field = Keyword.get(opts, :handle_field, "ref")

    Rust.item(AST.render_item_native(resource_handle_decode_ast(name, function_name, field)))
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
