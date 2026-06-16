defmodule RustQ.NativeCodegen.Decoders.Type do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec path_parts(term()) :: R.nif_result(String.t())
  defrust path_parts(term) do
    parts = unwrap!(Super.decode_string_list(term))
    ok(parts.join("::"))
  end

  @spec decode_lifetime_list(term()) :: R.nif_result(R.vec(String.t()))
  defrust decode_lifetime_list(term) do
    Super.decode_string_list(term)
  end

  @spec decode_type_path(term()) :: R.nif_result(Type.t())
  defrust decode_type_path(term) do
    parts = unwrap!(Super.decode_string_list(unwrap!(required_field(term, "parts"))))
    lifetimes = unwrap!(decode_lifetime_list(unwrap!(required_field(term, "lifetimes"))))
    generics = unwrap!(Super.decode_type_list(unwrap!(required_field(term, "generics"))))
    Super.parse_type_path_with_generics(parts, lifetimes, generics)
  end

  @spec decode_type_unit(term()) :: R.nif_result(Type.t())
  defrust decode_type_unit(term) do
    Super.parse_type_unit(term)
  end

  @spec decode_type_ref(term()) :: R.nif_result(Type.t())
  defrust decode_type_ref(term) do
    inner = unwrap!(Super.decode_type(unwrap!(required_field(term, "inner"))))
    mutable = unwrap!(unwrap!(required_field(term, "mutable")).decode())
    lifetime = unwrap!(optional_atom_key(term, "lifetime"))
    Super.parse_type_ref(inner, mutable, lifetime)
  end

  @spec decode_type_option(term()) :: R.nif_result(Type.t())
  defrust decode_type_option(term) do
    inner = unwrap!(Super.decode_type(unwrap!(required_field(term, "inner"))))
    Super.parse_type_generic("Option", [inner])
  end

  @spec decode_type_result(term()) :: R.nif_result(Type.t())
  defrust decode_type_result(term) do
    ok = unwrap!(Super.decode_type(unwrap!(required_field(term, "ok"))))
    error = unwrap!(Super.decode_type(unwrap!(required_field(term, "error"))))
    Super.parse_type_generic("Result", [ok, error])
  end

  @spec decode_type_nif_result(term()) :: R.nif_result(Type.t())
  defrust decode_type_nif_result(term) do
    inner = unwrap!(Super.decode_type(unwrap!(required_field(term, "inner"))))
    Super.parse_type_generic("NifResult", [inner])
  end

  @spec decode_type_vec(term()) :: R.nif_result(Type.t())
  defrust decode_type_vec(term) do
    inner = unwrap!(Super.decode_type(unwrap!(required_field(term, "inner"))))
    Super.parse_type_generic("Vec", [inner])
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
