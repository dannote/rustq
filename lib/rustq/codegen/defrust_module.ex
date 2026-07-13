defmodule RustQ.Codegen.DefrustModule do
  @moduledoc false

  @native_sources [
    "native/rustq_nif/src/decode.rs",
    "native/rustq_nif/src/parse.rs",
    "native/rustq_nif/src/parse_item.rs",
    "native/rustq_nif/src/parse_type.rs"
  ]

  defmacro __using__(opts) do
    opts =
      Keyword.update(opts, :rust_sources, @native_sources, fn sources ->
        (@native_sources ++ List.wrap(sources)) |> Enum.uniq()
      end)

    quote do
      use RustQ.Meta, unquote(opts)

      alias RustQ.Type, as: R

      @before_compile RustQ.Codegen.DefrustModule
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
    end
  end
end
