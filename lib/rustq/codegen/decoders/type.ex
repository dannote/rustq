defmodule RustQ.Codegen.Decoders.Type do
  @moduledoc false

  use RustQ.Codegen.DefrustModule,
    callable_modules: [RustQ.Codegen.DecoderHelpers, RustQ.Codegen.Helpers]

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
    parts = required_string_list(term, "parts")
    lifetimes = decode_lifetime_list(required_field(term, "lifetimes"))
    generics = required_type_list(term, "generics")
    Super.parse_type_path_with_generics(parts, lifetimes, generics)
  end

  @spec decode_type_unit(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_unit(term) do
    Super.parse_type_unit(term)
  end

  @spec decode_type_raw(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_raw(term) do
    source = required_field(term, "source").decode()
    Super.parse_type_raw(source)
  end

  @spec decode_type_ref(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_ref(term) do
    inner = required_type(term, "inner")
    mutable = required_field(term, "mutable").decode()
    lifetime = optional_atom_key(term, "lifetime")
    Super.parse_type_ref(inner, mutable, lifetime)
  end

  @spec decode_type_option(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_option(term) do
    Super.parse_type_generic("Option", [required_type(term, "inner")])
  end

  @spec decode_type_result(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_result(term) do
    Super.parse_type_generic("Result", [required_type(term, "ok"), required_type(term, "error")])
  end

  @spec decode_type_nif_result(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_nif_result(term) do
    Super.parse_type_generic("NifResult", [required_type(term, "inner")])
  end

  @spec decode_type_vec(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_vec(term) do
    Super.parse_type_generic("Vec", [required_type(term, "inner")])
  end

  @spec decode_type_slice(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_slice(term) do
    Super.parse_type_slice(required_type(term, "inner"))
  end

  @spec decode_type_array(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_array(term) do
    Super.parse_type_array(required_type(term, "inner"), required_field(term, "size"))
  end

  @spec decode_type_tuple(term()) :: R.nif_result(R.path(:Type))
  defrust decode_type_tuple(term) do
    Super.parse_type_tuple(required_type_list(term, "items"))
  end
end
