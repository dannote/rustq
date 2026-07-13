defmodule RustQ.Rustler.Resource do
  @moduledoc """
  Generates Rustler resource structs, handles, decoders, and initialization helpers.
  """

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.ItemBuilder, as: I
  alias RustQ.Rust.Identifier

  import RustQ.Rust.AST.ItemBuilder, only: [field: 3, function: 3, impl: 3]

  require A
  require I

  @doc "Builds the resource struct and its `rustler::Resource` implementation."
  @spec items(atom() | String.t(), keyword()) :: [AST.Struct.t() | AST.Impl.t()]
  def items(name, opts \\ []) do
    [resource_struct_ast(name, Keyword.get(opts, :fields, [])), resource_impl_ast(name)]
  end

  defp resource_struct_ast(name, fields) do
    I.struct Identifier.atom!(to_string(name)) do
      Enum.map(fields, fn {field_name, type} -> field(field_name, type, vis: :pub) end)
    end
  end

  defp resource_impl_ast(name) do
    impl A.type_path(name), trait: [:rustler, :Resource], attrs: [A.resource_impl_attr()] do
      []
    end
  end

  @doc "Builds a type alias for `ResourceArc<name>`."
  @spec type_alias(atom() | String.t(), keyword()) :: AST.TypeAlias.t()
  def type_alias(name, opts \\ []) do
    alias_name = Keyword.get(opts, :as, "#{name}Resource")

    A.type_alias(
      Identifier.atom!(to_string(alias_name)),
      resource_arc_type(name),
      opts
    )
  end

  @doc "Builds the `ResourceArc<name>` type."
  @spec arc_type(atom() | String.t()) :: AST.TypePath.t()
  def arc_type(name), do: resource_arc_type(name)

  @doc "Builds resource items plus a decoder for an Elixir-facing handle."
  @spec handle_items(atom() | String.t(), keyword()) :: [AST.item()]
  def handle_items(name, opts \\ []) do
    items(name, opts) ++ [handle_decoder(name, opts)]
  end

  @doc "Builds a decoder for `ResourceArc<name>`."
  @spec decoder(atom() | String.t(), keyword()) :: AST.Function.t()
  def decoder(name, opts \\ []) do
    function_name = Keyword.get(opts, :fn, "decode_#{Macro.underscore(to_string(name))}_resource")
    resource_decode_ast(name, function_name)
  end

  @doc "Builds a decoder for an Elixir-facing resource handle."
  @spec handle_decoder(atom() | String.t(), keyword()) :: AST.Function.t()
  def handle_decoder(name, opts \\ []) do
    function_name =
      Keyword.get(opts, :decoder, "decode_#{Macro.underscore(to_string(name))}_handle")

    resource_handle_decode_ast(name, function_name, Keyword.get(opts, :handle_field, "ref"))
  end

  defp resource_decode_ast(name, function_name) do
    resource_type = resource_arc_type(name)

    function Identifier.atom!(to_string(function_name)),
      lifetimes: [:a],
      args: [term: A.type_path(:Term, lifetimes: [:a])],
      returns: %AST.TypeNifResult{inner: resource_type} do
      A.return(A.method(:term, :decode, [], generics: [resource_type]))
    end
  end

  defp resource_handle_decode_ast(name, function_name, field) do
    resource_type = resource_arc_type(name)

    function Identifier.atom!(to_string(function_name)),
      lifetimes: [:a],
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

  @doc "Builds the resource registration macro invocation."
  @spec init(atom() | String.t()) :: AST.MacroItemCall.t()
  def init(name), do: A.macro_item_call([:rustler, :resource], [name, :env])
end
