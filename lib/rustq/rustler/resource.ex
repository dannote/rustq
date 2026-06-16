defmodule RustQ.Rustler.Resource do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A

  @decode_template ~R"""
  fn __rq_decode_fn<'a>(term: Term<'a>) -> NifResult<ResourceArc<__rq_Resource>> {
      term.decode::<ResourceArc<__rq_Resource>>()
  }
  """

  @handle_decode_template ~R"""
  fn __rq_decode_fn<'a>(term: Term<'a>) -> NifResult<ResourceArc<__rq_Resource>> {
      term.map_get(Atom::from_bytes(term.get_env(), __rq_field!())?)?
          .decode::<ResourceArc<__rq_Resource>>()
  }
  """

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

    Rust.item(
      RustQ.render!(@decode_template, "rustler_resource_decode.rs",
        bind: [Resource: name, decode_fn: function_name]
      )
    )
  end

  @spec handle_decode(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def handle_decode(name, opts \\ []) do
    function_name =
      Keyword.get(opts, :decoder, "decode_#{Macro.underscore(to_string(name))}_handle")

    field = Keyword.get(opts, :handle_field, "ref")

    Rust.item(
      RustQ.render!(@handle_decode_template, "rustler_resource_handle_decode.rs",
        bind: [Resource: name, decode_fn: function_name, field: {:expr, byte_string(field)}]
      )
    )
  end

  defp byte_string(field) when is_atom(field), do: byte_string(Atom.to_string(field))
  defp byte_string(field) when is_binary(field), do: "b#{inspect(field)}"

  @spec init(atom() | String.t()) :: Rust.Fragment.t()
  def init(name) do
    Rust.item("rustler::resource!(#{name}, env);")
  end
end
