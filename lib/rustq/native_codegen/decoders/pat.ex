defmodule RustQ.NativeCodegen.Decoders.Pat do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec decode_pat_var(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())

    if mutable do
      pat!(mut_ident(ident))
    else
      pat!(ident(ident))
    end
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
    path = unwrap!(required_path(term, "path"))
    pat!(path(path))
  end

  @spec decode_pat_literal(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_literal(term) do
    Super.decode_pat_literal_value(unwrap!(required_field(term, "value")))
  end

  @spec decode_pat_some(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_some(term) do
    pat = unwrap!(required_pat(term, "pattern"))
    pat!(some(pat))
  end

  @spec decode_pat_ok(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_ok(term) do
    pat = unwrap!(required_pat(term, "pattern"))
    pat!({:ok, pat})
  end

  @spec decode_pat_err(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_err(term) do
    pat = unwrap!(required_pat(term, "pattern"))
    pat!({:error, pat})
  end

  @spec decode_pat_tuple(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_tuple(term) do
    patterns = unwrap!(required_pat_list(term, "patterns"))
    pat!(tuple(patterns))
  end

  @spec decode_pat_path_tuple(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_path_tuple(term) do
    path = unwrap!(required_path(term, "path"))
    patterns = unwrap!(required_pat_list(term, "patterns"))
    pat!(path_tuple(path, patterns))
  end

  @spec decode_pat_struct(term()) :: R.nif_result(Pat.t())
  defrust decode_pat_struct(term) do
    path = unwrap!(required_path(term, "path"))
    fields = unwrap!(Super.decode_pat_struct_fields(unwrap!(required_field(term, "fields"))))
    pat!(struct(path, fields))
  end
end
