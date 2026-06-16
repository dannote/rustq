defmodule RustQ.Meta.Type do
  @moduledoc false

  defstruct [:kind, :rust]

  @type t :: %__MODULE__{kind: atom(), rust: String.t()}

  @spec from_spec_ast(Macro.t()) :: t()
  def from_spec_ast(ast), do: parse(ast)

  defp parse({{:., _, [module, function]}, _, args}) do
    parse_remote(module, function, args)
  end

  defp parse({:__aliases__, _, parts}) do
    %__MODULE__{kind: :type, rust: Enum.map_join(parts, "::", &to_string/1)}
  end

  defp parse(atom) when is_atom(atom) do
    %__MODULE__{kind: :type, rust: Atom.to_string(atom)}
  end

  defp parse_remote(module, function, args) do
    if type_module?(module) do
      parse_rust_type(function, args)
    else
      parse_external_type(module, function, args)
    end
  end

  defp type_module?({:__aliases__, _, [:R]}), do: true
  defp type_module?({:__aliases__, _, [:RustType]}), do: true
  defp type_module?({:__aliases__, _, [:RustQ, :Type]}), do: true
  defp type_module?(_module), do: false

  defp parse_rust_type(:atom, []), do: type(:atom, "Atom")
  defp parse_rust_type(:bool, []), do: type(:bool, "bool")
  defp parse_rust_type(:f32, []), do: type(:f32, "f32")
  defp parse_rust_type(:f64, []), do: type(:f64, "f64")
  defp parse_rust_type(:i64, []), do: type(:i64, "i64")
  defp parse_rust_type(:term, []), do: type(:term, "Term<'a>")
  defp parse_rust_type(:u8, []), do: type(:u8, "u8")
  defp parse_rust_type(:u32, []), do: type(:u32, "u32")
  defp parse_rust_type(:unit, []), do: type(:unit, "()")

  defp parse_rust_type(:ref, [inner]), do: type(:ref, "&#{parse(inner).rust}")
  defp parse_rust_type(:mut_ref, [inner]), do: type(:mut_ref, "&mut #{parse(inner).rust}")
  defp parse_rust_type(:option, [inner]), do: type(:option, "Option<#{parse(inner).rust}>")
  defp parse_rust_type(:vec, [inner]), do: type(:vec, "Vec<#{parse(inner).rust}>")

  defp parse_rust_type(:result, [ok, error]) do
    type(:result, "Result<#{parse(ok).rust}, #{parse(error).rust}>")
  end

  defp parse_rust_type(:nif_result, [inner]),
    do: type(:nif_result, "NifResult<#{parse(inner).rust}>")

  defp parse_rust_type(function, args) do
    rendered_args = Enum.map_join(args, ", ", &parse(&1).rust)
    type(:type, "#{function}<#{rendered_args}>")
  end

  defp parse_external_type({:__aliases__, _, parts}, :t, []) do
    type(:type, parts |> List.last() |> to_string())
  end

  defp parse_external_type({:__aliases__, _, parts}, function, args) do
    path = Enum.map_join(parts ++ [function], "::", &to_string/1)

    case args do
      [] -> type(:type, path)
      args -> type(:type, "#{path}<#{Enum.map_join(args, ", ", &parse(&1).rust)}>")
    end
  end

  defp parse_external_type(_module, function, _args), do: type(:type, Atom.to_string(function))

  defp type(kind, rust), do: %__MODULE__{kind: kind, rust: rust}
end
