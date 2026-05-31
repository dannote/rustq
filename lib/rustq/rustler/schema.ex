defmodule RustQ.Rustler.Schema do
  @moduledoc """
  Ecto-inspired DSL for Rustler interop schemas.
  """

  defstruct module_prefix: nil,
            rust_prefix: "Ex",
            tag_field: :__struct__,
            nodes: [],
            enums: []

  @type field :: {atom(), RustQ.Rust.rust_type(), keyword()}
  @type schema_node :: {atom(), [field()], keyword()}
  @type enum_decl :: {atom(), keyword()}
  @type t :: %__MODULE__{
          module_prefix: module(),
          rust_prefix: String.t(),
          tag_field: atom(),
          nodes: [schema_node()],
          enums: [enum_decl()]
        }

  defmacro __using__(_opts) do
    quote do
      import RustQ.Rustler.Schema

      Module.register_attribute(__MODULE__, :rustq_schema_nodes, accumulate: true)
      Module.register_attribute(__MODULE__, :rustq_schema_enums, accumulate: true)
      @rustq_schema_rust_prefix "Ex"
      @rustq_schema_tag_field :__struct__
      @before_compile RustQ.Rustler.Schema
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      alias RustQ.Rustler.Schema, as: RustlerSchema

      def schema do
        %RustlerSchema{
          module_prefix: @rustq_schema_module_prefix,
          rust_prefix: @rustq_schema_rust_prefix,
          tag_field: @rustq_schema_tag_field,
          nodes: Enum.reverse(@rustq_schema_nodes),
          enums: Enum.reverse(@rustq_schema_enums)
        }
      end

      def rust_items do
        RustlerSchema.rust_items(schema())
      end
    end
  end

  defmacro schema(module_prefix, do: block) do
    module_prefix = Macro.expand(module_prefix, __CALLER__)

    quote do
      @rustq_schema_module_prefix unquote(module_prefix)
      unquote(block)
    end
  end

  defmacro rust_prefix(prefix) do
    quote do
      @rustq_schema_rust_prefix unquote(prefix)
    end
  end

  defmacro tag_field(field) do
    quote do
      @rustq_schema_tag_field unquote(field)
    end
  end

  defmacro node(name, opts \\ [], do: block) do
    name = ast_name(name)
    fields = extract_fields(block)

    quote do
      @rustq_schema_nodes {unquote(name), unquote(Macro.escape(fields)),
                           unquote(Macro.escape(opts))}
    end
  end

  defmacro tagged_enum(name, opts \\ [], do: block) do
    name = ast_name(name)
    opts = Keyword.merge(opts, extract_enum_opts(block))

    quote do
      @rustq_schema_enums {unquote(name), unquote(Macro.escape(opts))}
    end
  end

  @spec rust_items(%__MODULE__{}) :: [RustQ.Rust.Fragment.t()]
  def rust_items(%__MODULE__{} = schema) do
    schema.nodes
    |> Enum.map(&nif_struct(schema, &1))
    |> Kernel.++(Enum.flat_map(schema.enums, &tagged_enum_items(schema, &1)))
  end

  defp nif_struct(schema, {name, fields, opts}) do
    RustQ.Rustler.nif_struct(rust_name(schema, name), module_name(schema, name),
      fields: Enum.map(fields, fn {field, type, _opts} -> {field, rust_type(schema, type)} end),
      attrs: Keyword.get(opts, :attrs, [])
    )
  end

  defp tagged_enum_items(schema, {name, opts}) do
    variants =
      opts
      |> Keyword.get(:variants, :all)
      |> enum_variants(schema)
      |> Enum.map(fn variant ->
        {variant,
         [
           type: rust_name(schema, variant),
           module: elixir_module_name(schema, variant)
         ]}
      end)

    RustQ.Rustler.tagged_enum(Keyword.get(opts, :rust, rust_name(schema, name)),
      tag: tag_expr(schema.tag_field),
      unknown: Keyword.get(opts, :unknown, :unknown_variant),
      variants: variants,
      attrs: Keyword.get(opts, :attrs, [])
    )
  end

  defp enum_variants(:all, schema), do: Enum.map(schema.nodes, &elem(&1, 0))
  defp enum_variants(variants, _schema), do: List.wrap(variants)

  defp rust_name(schema, name), do: "#{schema.rust_prefix}#{name}"

  defp module_name(schema, name) do
    "#{schema.module_prefix}.#{name}"
    |> String.replace_prefix("Elixir.", "")
  end

  defp elixir_module_name(schema, name), do: "Elixir.#{module_name(schema, name)}"

  defp tag_expr(:__struct__), do: "atom_struct()"
  defp tag_expr(field), do: "atoms::#{field}()"

  defp rust_type(_schema, :string), do: :String
  defp rust_type(_schema, :boolean), do: :bool
  defp rust_type(_schema, type), do: type

  defp extract_fields(block) do
    block
    |> block_expressions()
    |> Enum.map(fn
      {:field, _meta, [name, type]} -> {name, type, []}
      {:field, _meta, [name, type, opts]} -> {name, type, opts}
      other -> raise ArgumentError, "unsupported node expression: #{Macro.to_string(other)}"
    end)
  end

  defp extract_enum_opts(block) do
    block
    |> block_expressions()
    |> Enum.map(fn
      {:variants, _meta, [variants]} ->
        {:variants, extract_variants(variants)}

      {:rust, _meta, [name]} ->
        {:rust, ast_name(name)}

      {:unknown, _meta, [name]} ->
        {:unknown, name}

      other ->
        raise ArgumentError, "unsupported tagged_enum expression: #{Macro.to_string(other)}"
    end)
  end

  defp extract_variants(:all), do: :all

  defp extract_variants(variants) when is_list(variants) do
    Enum.map(variants, &ast_name/1)
  end

  defp ast_name({:__aliases__, _meta, parts}), do: List.last(parts)
  defp ast_name(name) when is_atom(name), do: name

  defp block_expressions({:__block__, _meta, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]
end
