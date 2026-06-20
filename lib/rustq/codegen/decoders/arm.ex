defmodule RustQ.Codegen.Decoders.Arm do
  @moduledoc """
  Emits native decoder helpers for Rust match arms.
  """

  use RustQ.Codegen.DefrustModule

  @spec decode_arm(term()) :: R.nif_result(R.path(:Arm))
  defrust decode_arm(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Arm"))
    pat_term = unwrap!(required_field(term, "pattern"))
    block = unwrap!(Super.decode_block(unwrap!(required_field(term, "body"))))

    if unwrap!(struct_name(pat_term)) == "Elixir.RustQ.Rust.AST.PatAtomGuard" do
      Super.decode_atom_guard_arm(pat_term, block)
    else
      pat = unwrap!(Super.decode_pat(pat_term))
      Super.parse_block_arm(pat, block)
    end
  end
end
