defmodule RustQ.Rustler.TaggedEnum do
  @moduledoc false

  use RustQ.Sigil

  alias RustQ.Rust

  @decoder_template ~R"""
  impl<'a> rustler::Decoder<'a> for __Enum {
      fn decode(term: rustler::Term<'a>) -> rustler::NifResult<Self> {
          use rustler::Decoder;
          let env = term.get_env();
          let module: rustler::Atom = term.map_get(__expr_tag!())?.decode()?;
          let name_str = module.to_term(env).atom_to_string()?;

          match name_str.as_str() {
              __splice_arms => unreachable!(),
          }
      }
  }
  """

  @encoder_template ~R"""
  impl rustler::Encoder for __Enum {
      fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a> {
          match self {
              __splice_arms => unreachable!(),
          }
      }
  }
  """

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    variants = Keyword.fetch!(opts, :variants)
    tag = Keyword.get(opts, :tag, "atom_struct()")
    unknown = Keyword.get(opts, :unknown, "unknown_variant")

    [
      enum(name, variants, opts),
      decoder(name, variants, tag, unknown),
      encoder(name, variants)
    ]
  end

  defp enum(name, variants, opts) do
    name
    |> Rust.enum(
      vis: Keyword.get(opts, :vis, :pub),
      derive: Keyword.get(opts, :derive, [:Clone, :Debug]),
      variants: Enum.map(variants, &variant/1),
      attrs: Keyword.get(opts, :attrs, [])
    )
    |> Rust.to_fragment()
    |> Rust.item()
  end

  defp decoder(name, variants, tag, unknown) do
    Rust.item(
      RustQ.render!(@decoder_template, "rustler_tagged_enum_decoder.rs",
        bind: [Enum: name, tag: Rust.expr(tag)],
        splice: [arms: Enum.map(variants, &decode_arm(name, &1)) ++ [unknown_arm(unknown)]]
      )
    )
  end

  defp encoder(name, variants) do
    Rust.item(
      RustQ.render!(@encoder_template, "rustler_tagged_enum_encoder.rs",
        bind: [Enum: name],
        splice: [arms: Enum.map(variants, &encode_arm(name, &1))]
      )
    )
  end

  defp variant({variant, opts}) do
    {variant, [tuple: [Keyword.fetch!(opts, :type)]]}
  end

  defp decode_arm(enum_name, {variant, opts}) do
    module = Keyword.fetch!(opts, :module)

    Rust.arm(
      inspect(module),
      "Ok(#{enum_name}::#{variant}(Decoder::decode(term)?))"
    )
  end

  defp encode_arm(enum_name, {variant, _opts}) do
    Rust.arm("#{enum_name}::#{variant}(value)", "value.encode(env)")
  end

  defp unknown_arm(unknown) do
    Rust.arm("_", ~s|Err(rustler::Error::RaiseAtom("#{unknown}"))|)
  end
end
