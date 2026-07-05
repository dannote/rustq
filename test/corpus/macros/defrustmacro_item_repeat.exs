defmodule RustQ.Corpus.Macros.DefrustmacroItemRepeat do
  @moduledoc "Item-generating defrustmacro with repeated descriptor rows."

  use RustQ.Meta

  alias RustQ.Type, as: R

  @type field :: %{
          required(:id) => R.u32(),
          required(:name) => R.raw(:"&'static str"),
          required(:repeated) => R.bool(),
          required(:decode) => R.raw(:"fn()")
        }

  @spec build_fields(R.slice(R.path(:Field))) :: R.nif_result(R.unit())
  defrust build_fields(_fields) do
    :ok
  end

  defrustmacro descriptor(
                 fn: name(:ident),
                 fields:
                   repeat do
                     field_id(:literal)
                     field_name(:literal)
                     field_mode(:ident)
                     field_decode(:ident)
                   end
               ) do
    @spec name() :: R.nif_result(R.unit())
    defrust name() do
      build_fields(
        ref(
          array([
            repeat fields do
              struct_literal(Field,
                id: field_id,
                name: field_name,
                repeated: repeated!(field_mode),
                decode: field_decode
              )
            end
          ])
        )
      )
    end
  end
end
