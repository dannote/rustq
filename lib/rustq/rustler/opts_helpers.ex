defmodule RustQ.Rustler.OptsHelpers do
  @moduledoc false

  use RustQ.Meta
  use RustQ.Sigil

  alias RustQ.Rust
  alias RustQ.Rustler.HelperSelection
  alias RustQ.Type, as: R

  @names [
    :decode_opts,
    :decode_args,
    :opt_term,
    :opt_f32,
    :opt_f32_option,
    :opt_f32_default,
    :opt_bool_option,
    :opt_atom_option
  ]

  @rusty_names @names -- [:opt_f32]

  @templates %{
    opt_f32: ~R"""
    fn opt_f32<'a>(opts: &[(Atom, Term<'a>)], key: Atom) -> NifResult<f32> {
        opt_f32_default(opts, key, f32::NAN).and_then(|value| {
            if value.is_nan() {
                Err(rustler::Error::BadArg)
            } else {
                Ok(value)
            }
        })
    }
    """
  }

  @spec decode_opts(term()) :: R.nif_result(R.vec({R.path(:Atom), term()}))
  defrust decode_opts(term) do
    decode_as(unwrap!(term.map_get(Atoms.opts())), R.vec({R.path(:Atom), term()}))
  end

  @spec decode_args(term()) :: R.nif_result(R.vec(term()))
  defrust decode_args(term) do
    decode_as(unwrap!(term.map_get(Atoms.args())), R.vec(term()))
  end

  @spec opt_term(R.slice({R.path(:Atom), term()}), R.path(:Atom)) :: R.option(term())
  defrust opt_term(opts, key) do
    for {atom, term} <- opts.iter() do
      if deref(atom) == key do
        return!(deref(term))
      end
    end

    nil
  end

  @spec opt_f32_option(R.slice({R.path(:Atom), term()}), R.path(:Atom)) ::
          R.nif_result(R.option(R.f32()))
  defrust opt_f32_option(opts, key) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, cast(decode_as!(term, R.f64()), :f32)}
      :none -> {:ok, nil}
    end
  end

  @spec opt_f32_default(R.slice({R.path(:Atom), term()}), R.path(:Atom), R.f32()) ::
          R.nif_result(R.f32())
  defrust opt_f32_default(opts, key, default) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, cast(decode_as!(term, R.f64()), :f32)}
      :none -> {:ok, default}
    end
  end

  @spec opt_bool_option(R.slice({R.path(:Atom), term()}), R.path(:Atom)) ::
          R.nif_result(R.option(R.bool()))
  defrust opt_bool_option(opts, key) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, decode_as!(term, R.bool())}
      :none -> {:ok, nil}
    end
  end

  @spec opt_atom_option(R.slice({R.path(:Atom), term()}), R.path(:Atom)) ::
          R.nif_result(R.option(R.path(:Atom)))
  defrust opt_atom_option(opts, key) do
    case opt_term(opts, key) do
      {:some, term} -> {:ok, decode_as!(term, R.path(:Atom))}
      :none -> {:ok, nil}
    end
  end

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    opts
    |> names()
    |> Enum.map(&helper_item/1)
  end

  defp helper_item(name) when name in @rusty_names, do: RustQ.Meta.defrust_item(__MODULE__, name)

  defp helper_item(name) do
    name
    |> template!()
    |> RustQ.render!("rustler_opts_helper.rs")
    |> Rust.item()
  end

  defp names(opts), do: HelperSelection.names(opts, @names)
  defp template!(name), do: Map.fetch!(@templates, name)
end
