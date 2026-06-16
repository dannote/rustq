defmodule RustQ.NativeCodegen.Decoders.Type do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Type, as: R

  @spec decode_type_path(term()) :: R.nif_result(Type.t())
  defrust decode_type_path(term) do
    parts = unwrap!(Super.path_parts(unwrap!(required_field(term, "parts"))))
    lifetimes = unwrap!(Super.decode_lifetime_list(unwrap!(required_field(term, "lifetimes"))))
    Super.parse_type_path(parts, lifetimes)
  end

  @spec decode_type_unit(term()) :: R.nif_result(Type.t())
  defrust decode_type_unit(_term) do
    Super.parse_type("()")
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
    Super.parse_type(ref(token_macro(:format, "\"Option<{}>\", quote!(#inner)")))
  end

  @spec decode_type_result(term()) :: R.nif_result(Type.t())
  defrust decode_type_result(term) do
    ok = unwrap!(Super.decode_type(unwrap!(required_field(term, "ok"))))
    error = unwrap!(Super.decode_type(unwrap!(required_field(term, "error"))))
    Super.parse_type(ref(token_macro(:format, "\"Result<{}, {}>\", quote!(#ok), quote!(#error)")))
  end

  @spec decode_type_nif_result(term()) :: R.nif_result(Type.t())
  defrust decode_type_nif_result(term) do
    inner = unwrap!(Super.decode_type(unwrap!(required_field(term, "inner"))))
    Super.parse_type(ref(token_macro(:format, "\"NifResult<{}>\", quote!(#inner)")))
  end

  @spec decode_type_vec(term()) :: R.nif_result(Type.t())
  defrust decode_type_vec(term) do
    inner = unwrap!(Super.decode_type(unwrap!(required_field(term, "inner"))))
    Super.parse_type(ref(token_macro(:format, "\"Vec<{}>\", quote!(#inner)")))
  end

  def asts, do: Enum.map(__rustq_asts__(), &%{&1 | vis: :crate})
end
