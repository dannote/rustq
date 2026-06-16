defmodule RustQ.Meta do
  @moduledoc """
  Valid-Elixir macro frontend for generating RustQ Rust fragments.

  `defrust` captures a normal Elixir function-shaped body plus its preceding
  `@spec`, lowers that quoted Elixir AST to Rust, and exposes generated Rust
  items through `__rustq_items__/0` and `__rustq_source__/0`.
  """

  alias RustQ.Meta.Lower
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  defmacro __using__(_opts) do
    quote do
      import RustQ.Meta
      Module.register_attribute(__MODULE__, :rustq_defs, accumulate: true)
      @before_compile RustQ.Meta
    end
  end

  defmacro defrust(call_ast, do: body_ast) do
    {name, _meta, args} = call_ast
    arity = length(args || [])

    stub_args =
      if arity == 0, do: [], else: for(index <- 1..arity//1, do: Macro.var(:"_arg#{index}", nil))

    quote do
      @rustq_defs {unquote(Macro.escape(call_ast)), unquote(Macro.escape(body_ast))}
      def unquote(name)(unquote_splicing(stub_args)), do: :erlang.nif_error(:rustq_defrust_stub)
    end
  end

  defmacro __before_compile__(env) do
    defs = Module.get_attribute(env.module, :rustq_defs) |> List.wrap() |> Enum.reverse()
    specs = Module.get_attribute(env.module, :spec) |> List.wrap()

    asts = Enum.map(defs, &build_ast(&1, specs))
    items = Enum.map(asts, &validate_item_ast/1)
    source = Enum.map_join(asts, "\n\n", &AST.render_function/1)

    quote do
      @doc false
      def __rustq_asts__, do: unquote(Macro.escape(asts))

      @doc false
      def __rustq_items__, do: unquote(Macro.escape(items))

      @doc false
      def __rustq_source__, do: unquote(source)
    end
  end

  defp build_ast({call_ast, body_ast}, specs) do
    {name, _meta, arg_asts} = call_ast
    arg_names = Enum.map(arg_asts, &arg_name!/1)
    {arg_types, return_type} = find_spec!(specs, name, length(arg_names))

    args = Enum.zip(arg_names, Enum.map(arg_types, & &1.rust))
    body = Lower.function_ast(body_ast, return_type)
    lifetime = if Enum.any?(arg_types ++ [return_type], &String.contains?(&1.rust, "'a")), do: :a

    %AST.Function{
      name: name,
      args: args,
      returns: return_type.rust,
      body: body,
      lifetime: lifetime
    }
  end

  defp validate_item_ast(%AST.Function{} = function) do
    RustQ.parse_fragment!(:item, AST.render_function(function))
  end

  defp arg_name!({name, _meta, context}) when is_atom(name) and is_atom(context), do: name

  defp arg_name!(other) do
    raise ArgumentError, "unsupported defrust argument: #{Macro.to_string(other)}"
  end

  defp find_spec!(specs, name, arity) do
    Enum.find_value(specs, fn
      {:spec, {:"::", _, [{^name, _, args}, return]}, _location} when length(args) == arity ->
        {Enum.map(args, &Type.from_spec_ast/1), Type.from_spec_ast(return)}

      _other ->
        nil
    end) ||
      raise ArgumentError,
            "missing @spec for defrust #{name}/#{arity}; define @spec immediately before or before defrust"
  end
end
