defmodule RustQ.NativeCodegen.Modules do
  @moduledoc false

  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.Schema

  import RustQ.Rust.AST.ItemBuilder

  require A
  require RustQ.Rust.AST.ItemBuilder

  def asts do
    [
      atoms_module(),
      ast_modules_module(),
      helper_items()
    ]
  end

  defp atoms_module do
    A.module(
      :atoms,
      [
        A.macro_item("rustler::atoms! {\n    ok,\n    error,\n}")
      ],
      vis: :crate
    )
  end

  defp ast_modules_module do
    constants =
      Schema.nodes()
      |> Enum.reject(&(&1.name in [:arm, :function_arg, :struct_field, :enum_variant]))
      |> Enum.map(fn node ->
        A.const(node.rust_const, "&str", node.rust_module, vis: :crate)
      end)

    A.module(:ast_modules, constants, vis: :crate)
  end

  defp helper_items do
    [
      function :atom,
        vis: :crate,
        args: [env: "Env", name: "&str"],
        returns: "NifResult<Atom>" do
        A.return(A.path_call([:Atom, :from_str], [:env, :name]))
      end
    ]
  end
end
