defmodule RustQ.NativeCodegen.Decoders.Pat do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_pat_var(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    pat!(ident(ident))
  end

  @spec decode_pat_wildcard(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_wildcard(_term) do
    pat!(:_)
  end

  @spec decode_pat_none(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_none(_term) do
    pat!(nil)
  end

  @spec decode_pat_path(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_path(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    pat!(path(path))
  end

  @spec decode_pat_literal(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_literal(term) do
    Super.decode_pat_literal_value(unwrap!(required_field(term, "value")))
  end

  @spec decode_pat_some(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_some(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    pat!(some(pat))
  end

  @spec decode_pat_ok(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_ok(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    pat!({:ok, pat})
  end

  @spec decode_pat_err(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_err(term) do
    pat = unwrap!(Super.decode_pat(unwrap!(required_field(term, "pattern"))))
    pat!({:error, pat})
  end

  @spec decode_pat_tuple(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_tuple(term) do
    patterns = unwrap!(Super.decode_pat_list(unwrap!(required_field(term, "patterns"))))
    pat!(tuple(patterns))
  end

  @spec decode_pat_path_tuple(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_path_tuple(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    patterns = unwrap!(Super.decode_pat_list(unwrap!(required_field(term, "patterns"))))
    pat!(path_tuple(path, patterns))
  end

  @spec decode_pat_struct(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_struct(term) do
    path = unwrap!(Super.parse_ast_path(unwrap!(required_field(term, "path"))))
    fields = unwrap!(Super.decode_pat_struct_fields(unwrap!(required_field(term, "fields"))))
    pat!(struct(path, fields))
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
