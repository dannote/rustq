defmodule RustQ.Corpus.Macros.DefrustmacroItemCall do
  @moduledoc "Semantic item macro call generated from defrustmacro metadata."

  use RustQ.Meta

  alias RustQ.Meta.AST, as: MetaAST
  alias RustQ.Type, as: R

  @type skip_field :: %{
          required(:id) => R.u32(),
          required(:repeated) => R.bool(),
          required(:bytes) => R.bool(),
          required(:skip) => R.raw(:SkipFn)
        }

  @spec build_fields(R.slice(R.path(:SkipField))) :: R.nif_result(R.unit())
  defrust build_fields(_fields) do
    :ok
  end

  defrustmacro descriptor(
                 fn: name(:ident),
                 decoder: decoder(:ident),
                 field: field(:ident),
                 definition: definition_name(:literal),
                 skip_fields:
                   repeat do
                     field_id(:literal)
                     field_repeated(:literal)
                     field_bytes(:literal)
                     field_skip(:ident)
                   end
               ) do
    @spec name(R.mut_ref(R.path(:Decoder, R.lifetime(:_))), R.u32()) :: R.nif_result(R.unit())
    defrust name(decoder, field) do
      build_fields(
        ref(
          array([
            repeat skip_fields do
              struct_literal(SkipField,
                id: field_id,
                repeated: field_repeated,
                bytes: field_bytes,
                skip: field_skip
              )
            end
          ])
        )
      )

      :ok
    end
  end

  def __rustq_corpus_fragments__ do
    [
      MetaAST.macro_item(__MODULE__, :descriptor),
      MetaAST.macro_call(__MODULE__, :descriptor,
        fn: :skip_document,
        decoder: :decoder,
        field: :field,
        definition: "Document",
        skip_fields: [
          [field_id: 1, field_repeated: false, field_bytes: false, field_skip: :skip_string],
          [field_id: 2, field_repeated: true, field_bytes: false, field_skip: :skip_child],
          [field_id: 3, field_repeated: false, field_bytes: true, field_skip: :skip_bytes]
        ]
      )
    ]
  end
end
