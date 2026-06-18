defmodule RustQ.NativeCodegen.DefrustModule do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use RustQ.Meta

      alias RustQ.Type, as: R

      @before_compile RustQ.NativeCodegen.DefrustModule
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
    end
  end
end
