defmodule RustQ.Codegen.Decoders.Pat do
  @moduledoc """
  Emits native decoder helpers for Rust patterns.
  """

  use RustQ.Codegen.DefrustModule

  @spec decode_pat_var(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_var(term) do
    ident = Super.format_ident_value(unwrap!(atom_key(term, "name")))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())

    Super.parse_var_pat(ident, mutable)
  end

  @spec decode_pat_wildcard(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_wildcard(term) do
    Super.parse_wildcard_pat(term)
  end

  @spec decode_pat_none(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_none(term) do
    Super.parse_none_pat(term)
  end

  @spec decode_pat_path(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_path(term) do
    path = unwrap!(required_path(term, "path"))
    Super.parse_path_pat(path)
  end

  @spec decode_pat_literal(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_literal(term) do
    Super.decode_pat_literal_value(unwrap!(required_field(term, "value")))
  end

  @spec decode_pat_some(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_some(term) do
    pat = unwrap!(required_pat(term, "pattern"))
    Super.parse_some_pat(pat)
  end

  @spec decode_pat_ok(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_ok(term) do
    pat = unwrap!(required_pat(term, "pattern"))
    Super.parse_ok_pat(pat)
  end

  @spec decode_pat_err(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_err(term) do
    pat = unwrap!(required_pat(term, "pattern"))
    Super.parse_err_pat(pat)
  end

  @spec decode_pat_tuple(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_tuple(term) do
    patterns = unwrap!(required_pat_list(term, "patterns"))
    Super.parse_tuple_pat(patterns)
  end

  @spec decode_pat_path_tuple(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_path_tuple(term) do
    path = unwrap!(required_path(term, "path"))
    patterns = unwrap!(required_pat_list(term, "patterns"))
    Super.parse_path_tuple_pat(path, patterns)
  end

  @spec decode_pat_struct(term()) :: R.nif_result(R.path(:Pat))
  defrust decode_pat_struct(term) do
    path = unwrap!(required_path(term, "path"))
    fields = unwrap!(Super.decode_pat_struct_fields(unwrap!(required_field(term, "fields"))))
    Super.parse_struct_pat(path, fields)
  end
end
