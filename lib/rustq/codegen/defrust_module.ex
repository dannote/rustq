defmodule RustQ.Codegen.DefrustModule do
  @moduledoc """
  Compile-time bridge for modules that define native support helpers with `defrust`.
  """

  defmacro __using__(_opts) do
    quote do
      use RustQ.Meta

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
