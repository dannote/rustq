defmodule RustQ.Syn do
  @moduledoc """
  Structural metadata for Rust source parsed with `syn`.

  This module exposes Rust AST metadata, not Rusty Elixir AST. It is intended
  for introspection tasks such as discovering enum variants, struct fields, or
  function signatures from Rust crates. Conversion from this metadata to
  `RustQ.Rust.AST` is intentionally explicit and partial.
  """

  alias RustQ.Error

  defmodule File do
    @moduledoc "Rust source file metadata."
    defstruct items: []

    @type t :: %__MODULE__{items: [RustQ.Syn.item()]}
  end

  defmodule Enum do
    @moduledoc "Rust enum metadata."
    defstruct [:name, :visibility, variants: []]

    @type t :: %__MODULE__{
            name: String.t(),
            visibility: :public | :private,
            variants: [String.t()]
          }
  end

  defmodule Struct do
    @moduledoc "Rust struct metadata."
    defstruct [:name, :visibility, fields: []]

    @type t :: %__MODULE__{
            name: String.t(),
            visibility: :public | :private,
            fields: [RustQ.Syn.Field.t()]
          }
  end

  defmodule Field do
    @moduledoc "Rust struct field metadata."
    defstruct [:name, :type]

    @type t :: %__MODULE__{name: String.t() | nil, type: String.t()}
  end

  defmodule Function do
    @moduledoc "Rust free function metadata."
    defstruct [:name, :visibility, args: [], returns: nil]

    @type t :: %__MODULE__{
            name: String.t(),
            visibility: :public | :private,
            args: [RustQ.Syn.Arg.t()],
            returns: String.t() | nil
          }
  end

  defmodule Arg do
    @moduledoc "Rust function argument metadata."
    defstruct [:name, :type]

    @type t :: %__MODULE__{name: String.t() | nil, type: String.t()}
  end

  defmodule Impl do
    @moduledoc "Rust impl block metadata."
    defstruct [:target, :trait, methods: []]

    @type t :: %__MODULE__{
            target: String.t(),
            trait: String.t() | nil,
            methods: [RustQ.Syn.Method.t()]
          }
  end

  defmodule Method do
    @moduledoc "Rust impl method metadata."
    defstruct [:name, :visibility, args: [], returns: nil]

    @type t :: %__MODULE__{
            name: String.t(),
            visibility: :public | :private,
            args: [RustQ.Syn.Arg.t()],
            returns: String.t() | nil
          }
  end

  @type item ::
          RustQ.Syn.Enum.t()
          | RustQ.Syn.Struct.t()
          | RustQ.Syn.Function.t()
          | RustQ.Syn.Impl.t()

  @doc "Parses Rust source into structural metadata."
  @spec parse(String.t()) :: {:ok, RustQ.Syn.File.t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    with {:ok, raw_items} <- RustQ.Native.syn_inspect(source) do
      {:ok, %RustQ.Syn.File{items: Elixir.Enum.map(raw_items, &decode_item!/1)}}
    end
  end

  @doc "Parses Rust source into structural metadata, raising on failure."
  @spec parse!(String.t()) :: RustQ.Syn.File.t()
  def parse!(source) when is_binary(source) do
    case parse(source) do
      {:ok, file} ->
        file

      {:error, errors} ->
        raise Error, message: "RustQ syn parse error: #{inspect(errors)}", errors: errors
    end
  end

  @doc "Reads and parses a Rust source file."
  @spec parse_file(Path.t()) :: {:ok, RustQ.Syn.File.t()} | {:error, term()}
  def parse_file(path) do
    with {:ok, source} <- Elixir.File.read(path) do
      parse(source)
    end
  end

  @doc "Reads and parses a Rust source file, raising on failure."
  @spec parse_file!(Path.t()) :: RustQ.Syn.File.t()
  def parse_file!(path) do
    path
    |> Elixir.File.read!()
    |> parse!()
  end

  @doc "Returns top-level Rust enum metadata from a parsed file."
  @spec enums(RustQ.Syn.File.t()) :: [RustQ.Syn.Enum.t()]
  def enums(%RustQ.Syn.File{items: items}),
    do: Elixir.Enum.filter(items, &match?(%RustQ.Syn.Enum{}, &1))

  @doc "Returns top-level Rust struct metadata from a parsed file."
  @spec structs(RustQ.Syn.File.t()) :: [RustQ.Syn.Struct.t()]
  def structs(%RustQ.Syn.File{items: items}),
    do: Elixir.Enum.filter(items, &match?(%RustQ.Syn.Struct{}, &1))

  @doc "Returns top-level Rust free function metadata from a parsed file."
  @spec functions(RustQ.Syn.File.t()) :: [RustQ.Syn.Function.t()]
  def functions(%RustQ.Syn.File{items: items}),
    do: Elixir.Enum.filter(items, &match?(%RustQ.Syn.Function{}, &1))

  @doc "Returns top-level Rust impl block metadata from a parsed file."
  @spec impls(RustQ.Syn.File.t()) :: [RustQ.Syn.Impl.t()]
  def impls(%RustQ.Syn.File{items: items}),
    do: Elixir.Enum.filter(items, &match?(%RustQ.Syn.Impl{}, &1))

  @doc "Returns methods from all top-level Rust impl blocks in a parsed file."
  @spec methods(RustQ.Syn.File.t()) :: [RustQ.Syn.Method.t()]
  def methods(%RustQ.Syn.File{} = file),
    do: file |> impls() |> Elixir.Enum.flat_map(& &1.methods)

  @doc "Returns variants for a named top-level enum from Rust source."
  @spec enum_variants(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def enum_variants(source, enum_name) when is_binary(source) and is_binary(enum_name),
    do: RustQ.Native.syn_enum_variants(source, enum_name)

  @doc "Returns variants for a named top-level enum from Rust source, raising on failure."
  @spec enum_variants!(String.t(), String.t()) :: [String.t()]
  def enum_variants!(source, enum_name) do
    case enum_variants(source, enum_name) do
      {:ok, variants} ->
        variants

      {:error, errors} ->
        raise Error, message: "RustQ enum introspection error: #{inspect(errors)}", errors: errors
    end
  end

  defp decode_item!({"enum", name, visibility, variants}) do
    %RustQ.Syn.Enum{name: name, visibility: decode_visibility!(visibility), variants: variants}
  end

  defp decode_item!({"struct", name, visibility, fields}) do
    %RustQ.Syn.Struct{
      name: name,
      visibility: decode_visibility!(visibility),
      fields:
        Elixir.Enum.map(fields, fn {name, type} -> %RustQ.Syn.Field{name: name, type: type} end)
    }
  end

  defp decode_item!({"function", name, visibility, args, returns}) do
    %RustQ.Syn.Function{
      name: name,
      visibility: decode_visibility!(visibility),
      args: decode_args(args),
      returns: returns
    }
  end

  defp decode_item!({"impl", target, trait, methods}) do
    %RustQ.Syn.Impl{
      target: target,
      trait: trait,
      methods: Elixir.Enum.map(methods, &decode_method!/1)
    }
  end

  defp decode_method!({"method", name, visibility, args, returns}) do
    %RustQ.Syn.Method{
      name: name,
      visibility: decode_visibility!(visibility),
      args: decode_args(args),
      returns: returns
    }
  end

  defp decode_args(args),
    do: Elixir.Enum.map(args, fn {name, type} -> %RustQ.Syn.Arg{name: name, type: type} end)

  defp decode_visibility!("public"), do: :public
  defp decode_visibility!("private"), do: :private
end
