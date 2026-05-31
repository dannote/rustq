defmodule RustQ.Rustler.Resource do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @struct_template ~R"""
  struct __Resource {
      __splice_fields: (),
  }
  """

  @impl_template ~R"""
  #[rustler::resource_impl]
  impl rustler::Resource for __Resource {}
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
end
