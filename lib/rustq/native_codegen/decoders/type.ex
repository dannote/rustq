defmodule RustQ.NativeCodegen.Decoders.Type do
  @moduledoc false

  use RustQ.NativeCodegen.DefrustModule

  @spec path_parts(term()) :: R.nif_result(String.t())
  defrust path_parts(term) do
    parts = unwrap!(Super.decode_string_list(term))
    ok(parts.join("::"))
  end

  @spec decode_lifetime_list(term()) :: R.nif_result(R.vec(String.t()))
  defrust decode_lifetime_list(term) do
    Super.decode_string_list(term)
  end

  @spec decode_type_path(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_path(term) do
    parts = unwrap!(required_string_list(term, "parts"))
    lifetimes = unwrap!(decode_lifetime_list(unwrap!(required_field(term, "lifetimes"))))
    generics = unwrap!(required_type_list(term, "generics"))
    Super.parse_type_path_with_generics(parts, lifetimes, generics)
  end

  @spec decode_type_unit(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_unit(term) do
    Super.parse_type_unit(term)
  end

  @spec decode_type_raw(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_raw(term) do
    source = unwrap!(unwrap!(required_field(term, "source")).decode())
    Super.parse_type_raw(source)
  end

  @spec decode_type_ref(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_ref(term) do
    inner = unwrap!(required_type(term, "inner"))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())
    lifetime = unwrap!(optional_atom_key(term, "lifetime"))
    Super.parse_type_ref(inner, mutable, lifetime)
  end

  @spec decode_type_option(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_option(term) do
    inner = unwrap!(required_type(term, "inner"))
    Super.parse_type_generic("Option", [inner])
  end

  @spec decode_type_result(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_result(term) do
    ok = unwrap!(required_type(term, "ok"))
    error = unwrap!(required_type(term, "error"))
    Super.parse_type_generic("Result", [ok, error])
  end

  @spec decode_type_nif_result(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_nif_result(term) do
    inner = unwrap!(required_type(term, "inner"))
    Super.parse_type_generic("NifResult", [inner])
  end

  @spec decode_type_vec(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_vec(term) do
    inner = unwrap!(required_type(term, "inner"))
    Super.parse_type_generic("Vec", [inner])
  end

  @spec decode_type_slice(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_slice(term) do
    inner = unwrap!(required_type(term, "inner"))
    Super.parse_type_slice(inner)
  end

  @spec decode_type_array(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_array(term) do
    inner = unwrap!(required_type(term, "inner"))
    size = unwrap!(required_field(term, "size"))
    Super.parse_type_array(inner, size)
  end
end
