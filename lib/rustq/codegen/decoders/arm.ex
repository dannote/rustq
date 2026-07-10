defmodule RustQ.Codegen.Decoders.Arm do
  @moduledoc """
  Emits native decoder helpers for Rust match arms.
  """

  use RustQ.Codegen.DefrustModule,
    callable_modules: [RustQ.Codegen.DecoderHelpers, RustQ.Codegen.Helpers]

  @spec decode_arm(term()) :: R.nif_result(R.path(:Arm))
  defrust decode_arm(term) do
    expect_struct(term, "Elixir.RustQ.Rust.AST.Arm")
    pat_term = required_field(term, "pattern")
    guard = Super.decode_optional_expr_field(term, "guard")
    block = Super.decode_block(required_field(term, "body"))

    if struct_name(pat_term) == "Elixir.RustQ.Rust.AST.PatAtomGuard" do
      Super.decode_atom_guard_arm(pat_term, block)
    else
      Super.parse_guarded_block_arm(Super.decode_pat(pat_term), guard, block)
    end
  end
end
