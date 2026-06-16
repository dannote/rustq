defmodule RustQ.NativeCodegen.Decoders.Arm do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_arm(term()) :: R.nif_result(Arm.t())
  defrust decode_arm(term) do
    unwrap!(expect_struct(term, "Elixir.RustQ.Rust.AST.Arm"))
    pat_term = unwrap!(required_field(term, "pattern"))
    block = unwrap!(Super.decode_block(unwrap!(required_field(term, "body"))))

    if unwrap!(struct_name(pat_term)) == "Elixir.RustQ.Rust.AST.PatAtomGuard" do
      Super.decode_atom_guard_arm(pat_term, block)
    else
      pat = unwrap!(Super.decode_pat(pat_term))
      raw_arm!("#pat => #block,")
    end
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
