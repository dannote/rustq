defmodule RustQ.Rustler.TaggedEnum do
  @moduledoc """
  Generates Rust enums decoded from tagged Elixir struct or map terms.
  """

  alias RustQ.Rust
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Builder, as: A
  alias RustQ.Rust.AST.PatternBuilder, as: P

  require A

  @spec build(atom() | String.t(), keyword()) :: [Rust.Fragment.t()]
  def build(name, opts) do
    variants = Keyword.fetch!(opts, :variants)
    tag = Keyword.get(opts, :tag, A.call(:atom_struct))
    unknown = Keyword.get(opts, :unknown, "unknown_variant")

    [
      enum(name, variants, opts),
      decoder(name, variants, tag, unknown),
      encoder(name, variants)
    ]
  end

  defp enum(name, variants, opts) do
    Rust.ast_item(%AST.Enum{
      name: ident_atom(name),
      vis: Keyword.get(opts, :vis, :pub),
      derive: Keyword.get(opts, :derive, [:Clone, :Debug]),
      variants: Enum.map(variants, &variant/1),
      attrs: Keyword.get(opts, :attrs, [])
    })
  end

  defp decoder(name, variants, tag, unknown) do
    impl =
      A.impl(A.type_path(name),
        lifetimes: [:a],
        trait: A.type_path([:rustler, :Decoder], lifetimes: [:a]),
        items: [decoder_function(name, variants, tag, unknown)]
      )

    Rust.ast_item(impl)
  end

  defp encoder(name, variants) do
    impl =
      A.impl(A.type_path(name),
        trait: A.type_path([:rustler, :Encoder]),
        items: [encoder_function(name, variants)]
      )

    Rust.ast_item(impl)
  end

  defp variant({variant, opts}) do
    %AST.EnumVariant{name: ident_atom(variant), tuple: [Keyword.fetch!(opts, :type)]}
  end

  defp decoder_function(enum_name, variants, tag, unknown) do
    %AST.Function{
      name: :decode,
      args: [A.arg(:term, A.type_path([:rustler, :Term], lifetimes: [:a]))],
      returns: A.type_path([:rustler, :NifResult], generics: [A.type_path(:Self)]),
      body: [
        A.let(:env, A.method(:term, :get_env)),
        A.let(
          :module,
          A.try(A.method(A.try(A.method(:term, :map_get, [tag])), :decode)),
          type: A.type_path([:rustler, :Atom])
        ),
        A.let(
          :name_str,
          A.try(A.method(A.method(:module, :to_term, [:env]), :atom_to_string))
        ),
        A.return(
          A.match_expr(
            A.method(:name_str, :as_str),
            Enum.map(variants, &decode_arm(ident_atom(enum_name), &1)) ++ [unknown_arm(unknown)]
          )
        )
      ]
    }
  end

  defp decode_arm(enum_name, {variant, opts}) do
    module = Keyword.fetch!(opts, :module)

    %AST.Arm{
      pattern: P.lit(module),
      body: [
        A.return(
          A.ok(
            A.path_call([ident_atom(enum_name), ident_atom(variant)], [
              A.try(A.path_call([:rustler, :Decoder, :decode], [:term]))
            ])
          )
        )
      ]
    }
  end

  defp encoder_function(enum_name, variants) do
    %AST.Function{
      name: :encode,
      lifetime: :a,
      args: [A.receiver(), A.arg(:env, A.type_path([:rustler, :Env], lifetimes: [:a]))],
      returns: A.type_path([:rustler, :Term], lifetimes: [:a]),
      body: [A.return(A.match_expr(A.var(:self), Enum.map(variants, &encode_arm(enum_name, &1))))]
    }
  end

  defp encode_arm(enum_name, {variant, _opts}) do
    %AST.Arm{
      pattern: P.path_tuple([ident_atom(enum_name), ident_atom(variant)], [:value]),
      body: [A.return(A.method(:value, :encode, [:env]))]
    }
  end

  defp unknown_arm(unknown) do
    %AST.Arm{
      pattern: P.wildcard(),
      body: [
        A.return(A.err(A.path_call([:rustler, :Error, :RaiseAtom], [A.lit(to_string(unknown))])))
      ]
    }
  end

  defp ident_atom(value) when is_atom(value), do: value
  defp ident_atom(value) when is_binary(value), do: RustQ.Atom.identifier!(value)
end
