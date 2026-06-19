defmodule RustQ.Rustler.TermHelpers do
  @moduledoc false

  use RustQ.Meta

  alias RustQ.Rust
  alias RustQ.Rustler.HelperSelection
  alias RustQ.Type, as: R

  @names [
    :get,
    :is_nil,
    :opt,
    :str_val,
    :bool_val,
    :f64_val,
    :list_val,
    :type_atom,
    :type_eq,
    :type_str
  ]

  @rusty_names @names

  @spec get(term(), R.path({:rustler, :Atom})) :: R.option(term())
  defrust get(term, key) do
    case term.map_get(key) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  @spec is_nil(term()) :: boolean()
  defrust is_nil(term) do
    if term.is_atom() do
      case term.atom_to_string() do
        {:ok, value} -> value == "nil"
        {:error, _reason} -> false
      end
    else
      false
    end
  end

  @spec opt(term(), R.path({:rustler, :Atom})) :: R.option(term())
  defrust opt(term, key) do
    case get(term, key) do
      {:some, value} ->
        if is_nil(value) do
          nil
        else
          value
        end

      :none ->
        nil
    end
  end

  @spec str_val(term(), R.path({:rustler, :Atom})) :: String.t()
  defrust str_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        case decode_as(value, String.t()) do
          {:ok, decoded} ->
            decoded

          {:error, _reason} ->
            value.atom_to_string().unwrap_or_default()
        end

      :none ->
        String.new()
    end
  end

  @spec bool_val(term(), R.path({:rustler, :Atom})) :: boolean()
  defrust bool_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        value.decode().unwrap_or_default()

      :none ->
        false
    end
  end

  @spec f64_val(term(), R.path({:rustler, :Atom})) :: R.f64()
  defrust f64_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        case decode_as(value, R.f64()) do
          {:ok, decoded} ->
            decoded

          {:error, _reason} ->
            case decode_as(value, R.i64()) do
              {:ok, decoded} -> cast(decoded, :f64)
              {:error, _reason} -> 0.0
            end
        end

      :none ->
        0.0
    end
  end

  @spec list_val(term(), R.path({:rustler, :Atom})) :: R.vec(term())
  defrust list_val(term, key) do
    case get(term, key) do
      {:some, value} ->
        value.decode().unwrap_or_default()

      :none ->
        Vec.new()
    end
  end

  @spec type_atom(term()) :: R.option(R.path({:rustler, :Atom}))
  defrust type_atom(term) do
    case get(term, Atoms.type()) do
      {:some, value} ->
        case decode_as(value, R.path({:rustler, :Atom})) do
          {:ok, decoded} -> decoded
          {:error, _reason} -> nil
        end

      :none ->
        nil
    end
  end

  @spec type_eq(term(), R.path({:rustler, :Atom})) :: boolean()
  defrust type_eq(term, expected) do
    type_atom(term) == some(expected)
  end

  @spec type_str(term()) :: String.t()
  defrust type_str(term) do
    case get(term, Atoms.type()) do
      {:some, value} ->
        case value.atom_to_string() do
          {:ok, decoded} -> decoded
          {:error, _reason} -> String.from("<no type>")
        end

      :none ->
        String.from("<no type>")
    end
  end

  @spec build(keyword()) :: [Rust.Fragment.t()]
  def build(opts \\ []) do
    opts
    |> names()
    |> Enum.map(&helper_item/1)
  end

  defp names(opts), do: HelperSelection.names(opts, @names)

  defp helper_item(name) when name in @rusty_names, do: RustQ.Meta.item(__MODULE__, name)
end
