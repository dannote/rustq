defmodule RustQ.Rust.AST.SchemaTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST.Schema

  test "derives nodes from AST modules and their typespecs" do
    nodes = Schema.nodes()

    assert function = Enum.find(nodes, &(&1.module == RustQ.Rust.AST.Function))
    assert function.name == :function
    assert function.rust_const == :FUNCTION
    assert function.rust_module == "Elixir.RustQ.Rust.AST.Function"
    assert function.category == :item
    assert {:body, _type} = List.keyfind(function.fields, :body, 0)
    refute List.keymember?(function.fields, :__struct__, 0)
  end

  test "filters nodes by category" do
    assert Enum.any?(Schema.nodes(:expr), &(&1.module == RustQ.Rust.AST.Var))
    refute Enum.any?(Schema.nodes(:expr), &(&1.module == RustQ.Rust.AST.Function))
  end
end

defmodule RustQ.Rust.AST.SchemaSampleTest do
  alias RustQ.Rust.AST.Schema

  use ExUnit.Case,
    async: true,
    parameterize:
      Enum.map(Schema.nodes(), fn node ->
        %{schema_node: node}
      end)

  test "behavioral sample contains every schema field", %{schema_node: node} do
    sample = RustQ.ASTSamples.sample_for(node.name)

    assert found = find_struct(sample, node.module),
           "sample for #{node.name} does not contain #{inspect(node.module)}"

    actual_fields = found |> Map.keys() |> Enum.reject(&(&1 == :__struct__)) |> MapSet.new()
    schema_fields = node.fields |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    assert actual_fields == schema_fields,
           "sample for #{node.name} does not match schema fields"
  end

  defp find_struct(%{__struct__: module} = struct, module), do: struct

  defp find_struct(%{__struct__: _module} = struct, target_module) do
    struct
    |> Map.from_struct()
    |> find_struct(target_module)
  end

  defp find_struct(map, target_module) when is_map(map) do
    map
    |> Map.values()
    |> Enum.find_value(&find_struct(&1, target_module))
  end

  defp find_struct(list, target_module) when is_list(list),
    do: Enum.find_value(list, &find_struct(&1, target_module))

  defp find_struct(tuple, target_module) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> find_struct(target_module)

  defp find_struct(_other, _target_module), do: nil
end
