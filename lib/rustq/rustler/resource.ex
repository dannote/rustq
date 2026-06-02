defmodule RustQ.Rustler.Resource do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @struct_template ~R"""
  struct __rq_Resource {
      __rq_fields: (),
  }
  """

  @impl_template ~R"""
  #[rustler::resource_impl]
  impl rustler::Resource for __rq_Resource {}
  """

  @decode_template ~R"""
  fn __rq_decode_fn<'a>(term: Term<'a>) -> NifResult<ResourceArc<__rq_Resource>> {
      term.decode::<ResourceArc<__rq_Resource>>()
  }
  """

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts \\ []) do
    fields =
      opts
      |> Keyword.get(:fields, [])
      |> Enum.map(fn {field, type} -> Rust.field(field, type, vis: :pub) end)

    [
      Rust.item(
        RustQ.render!(@struct_template, "rustler_resource_struct.rs",
          bind: [Resource: name],
          splice: [fields: fields]
        )
      ),
      Rust.item(RustQ.render!(@impl_template, "rustler_resource_impl.rs", bind: [Resource: name]))
    ]
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

  @spec decode(atom() | String.t(), keyword()) :: Rust.Fragment.t()
  def decode(name, opts \\ []) do
    function_name = Keyword.get(opts, :fn, "decode_#{Macro.underscore(to_string(name))}_resource")

    Rust.item(
      RustQ.render!(@decode_template, "rustler_resource_decode.rs",
        bind: [Resource: name, decode_fn: function_name]
      )
    )
  end

  @spec init(atom() | String.t()) :: Rust.Fragment.t()
  def init(name) do
    Rust.item("rustler::resource!(#{name}, env);")
  end
end
