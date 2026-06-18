defmodule RustQ.Meta.Type do
  @moduledoc """
  Structural metadata for an Elixir typespec lowered by RustQ.

  `RustQ.Spec.type/2` and `RustQ.Spec.aliases/1` return this struct. The
  `:kind` field is the primary semantic classification (`:f64`, `:bool`,
  `:tuple`, `:struct`, `:enum`, `:type`, and so on). The `:ast` field carries
  the RustQ Rust type AST used for rendering, `:rust` is its rendered Rust type,
  and `:meta` carries shape-specific metadata such as:

    * `:elements` for tuple element types
    * `:fields` for map/struct field types
    * `:elixir_name` for local aliases and enum aliases
    * `:elixir_module`, `:elixir_type`, and `:elixir_args` for external
      Elixir remote types such as `Skia.Path.t()`

  Prefer consuming this structure directly at codegen boundaries instead of
  parsing rendered Rust type strings.
  """

  alias RustQ.Rust.AST

  defguardp is_ast_tuple(tuple)
            when tuple_size(tuple) == 3 and is_atom(elem(tuple, 0)) and is_list(elem(tuple, 1)) and
                   is_list(elem(tuple, 2))

  defstruct [:kind, :rust, :ast, meta: %{}]

  @type t :: %__MODULE__{kind: atom(), rust: String.t(), ast: term(), meta: map()}

  @spec from_spec_ast(Macro.t(), map()) :: t()
  def from_spec_ast(ast, aliases \\ %{}), do: parse(ast, aliases)

  @spec type_aliases([term()]) :: map()
  def type_aliases(types) do
    raw =
      types
      |> List.wrap()
      |> Enum.reverse()
      |> Map.new(fn {:type, {:"::", _, [{name, _, args}, ast]}, _location} ->
        arity = args |> List.wrap() |> length()
        rust_name = name |> Atom.to_string() |> Macro.camelize()
        {{name, arity}, {name, ast, rust_name}}
      end)

    raw
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, aliases -> elem(resolve_alias(key, raw, aliases), 1) end)
  end

  defp resolve_alias(key, raw, aliases) do
    case Map.fetch(aliases, key) do
      {:ok, type} ->
        {type, aliases}

      :error ->
        {name, ast, rust_name} = Map.fetch!(raw, key)
        type = parse_type_alias(name, ast, rust_name, raw, aliases)
        aliases = Map.put(aliases, key, type)
        {type, aliases}
    end
  end

  defp parse_type_alias(name, ast, rust_name, raw, aliases) do
    cond do
      atom_union?(ast) ->
        type(:enum, path(rust_name), %{elixir_name: name, variants: union_members(ast)})

      option_union?(ast) ->
        [_nil, inner] = option_members(ast)
        {inner_type, _aliases} = parse_alias_type(inner, raw, aliases)

        type(:option, %AST.TypeOption{inner: inner_type.ast}, %{
          elixir_name: name,
          inner: inner_type
        })

      result_union?(ast) ->
        {ok, error} = result_members(ast)
        {ok_type, aliases} = parse_alias_type(ok, raw, aliases)
        {error_type, _aliases} = parse_alias_type(error, raw, aliases)

        type(:result, %AST.TypeResult{ok: ok_type.ast, error: error_type.ast}, %{
          elixir_name: name,
          ok: ok_type,
          error: error_type
        })

      tuple_union?(ast, raw, aliases) ->
        {variants, _aliases} = tuple_variants(ast, raw, aliases)

        type(:tuple_enum, path(rust_name), %{
          elixir_name: name,
          variants: variants
        })

      struct_type?(ast) ->
        {struct_rust_name, fields} = struct_type(ast)

        type(:struct, path(struct_rust_name), %{
          elixir_name: name,
          rust_name: struct_rust_name,
          fields: fields
        })

      map_type?(ast) ->
        {fields, _aliases} = map_fields(ast, raw, aliases)

        lifetimes =
          if Enum.any?(fields, fn {_name, type, _presence} ->
               String.contains?(type.rust, "'a")
             end), do: [:a], else: []

        type(:struct, %AST.TypePath{parts: [rust_name], lifetimes: lifetimes}, %{
          elixir_name: name,
          rust_name: rust_name,
          fields: fields
        })

      true ->
        type(:alias, path(rust_name), %{elixir_name: name, ast: ast})
    end
  end

  defp parse_alias_type({name, _meta, args} = ast, raw, aliases)
       when is_atom(name) and is_list(args) do
    key = {name, length(args)}

    if Map.has_key?(raw, key) do
      resolve_alias(key, raw, aliases)
    else
      {parse(ast, aliases), aliases}
    end
  end

  defp parse_alias_type(ast, _raw, aliases), do: {parse(ast, aliases), aliases}

  defp parse({{:., _, [module, function]}, _, args}, aliases),
    do: parse_remote(module, function, args, aliases)

  defp parse({:{}, _, elements}, aliases) do
    tuple_types = Enum.map(elements, &parse(&1, aliases))
    tuple_type(tuple_types)
  end

  defp parse({name, _, args}, aliases) when is_atom(name) and is_list(args) do
    case Map.get(aliases, {name, length(args)}) do
      nil -> parse_local_type(name, args, aliases)
      alias_type -> alias_type
    end
  end

  defp parse({:|, _, _args} = union, aliases) do
    cond do
      option_union?(union) ->
        [_nil, inner] = option_members(union)
        inner_type = parse(inner, aliases)
        type(:option, %AST.TypeOption{inner: inner_type.ast})

      result_union?(union) ->
        {ok, error} = result_members(union)
        ok_type = parse(ok, aliases)
        error_type = parse(error, aliases)
        type(:result, %AST.TypeResult{ok: ok_type.ast, error: error_type.ast})

      atom_union?(union) ->
        type(:enum, path(:Atom))

      true ->
        type(:type, path(:Term))
    end
  end

  defp parse({:__aliases__, _, parts}, _aliases), do: type(:type, %AST.TypePath{parts: parts})

  defp parse(tuple, aliases)
       when is_tuple(tuple) and tuple_size(tuple) > 0 and not is_ast_tuple(tuple) do
    tuple_types = tuple |> Tuple.to_list() |> Enum.map(&parse(&1, aliases))
    tuple_type(tuple_types)
  end

  defp parse(atom, _aliases) when is_atom(atom), do: type(:type, path(atom))

  defp parse_remote(module, function, args, aliases) do
    if type_module?(module),
      do: parse_rust_type(function, args, aliases),
      else: parse_external_type(module, function, args, aliases)
  end

  defp type_module?({:__aliases__, _, [:R]}), do: true
  defp type_module?({:__aliases__, _, [:RustType]}), do: true
  defp type_module?({:__aliases__, _, [:RustQ, :Type]}), do: true
  defp type_module?(_module), do: false

  defp parse_local_type(:atom, [], _aliases), do: type(:atom, path(:Atom))
  defp parse_local_type(:boolean, [], _aliases), do: type(:bool, path(:bool))
  defp parse_local_type(:integer, [], _aliases), do: type(:i64, path(:i64))
  defp parse_local_type(:float, [], _aliases), do: type(:f64, path(:f64))
  defp parse_local_type(:number, [], _aliases), do: type(:f64, path(:f64))

  defp parse_local_type(:term, [], _aliases),
    do: type(:term, %AST.TypePath{parts: [:Term], lifetimes: [:a]})

  defp parse_local_type(:binary, [], _aliases), do: type(:type, %AST.TypeVec{inner: path(:u8)})
  defp parse_local_type(name, args, aliases), do: parse_rust_type(name, args, aliases)

  defp parse_rust_type(:atom, [], _aliases), do: type(:atom, path(:Atom))
  defp parse_rust_type(:bool, [], _aliases), do: type(:bool, path(:bool))
  defp parse_rust_type(:f32, [], _aliases), do: type(:f32, path(:f32))
  defp parse_rust_type(:f64, [], _aliases), do: type(:f64, path(:f64))
  defp parse_rust_type(:i8, [], _aliases), do: type(:i8, path(:i8))
  defp parse_rust_type(:i16, [], _aliases), do: type(:i16, path(:i16))
  defp parse_rust_type(:i32, [], _aliases), do: type(:i32, path(:i32))
  defp parse_rust_type(:i64, [], _aliases), do: type(:i64, path(:i64))
  defp parse_rust_type(:isize, [], _aliases), do: type(:isize, path(:isize))
  defp parse_rust_type(:str, [], _aliases), do: type(:str, %AST.TypeRef{inner: path(:str)})

  defp parse_rust_type(:term, [], _aliases),
    do: type(:term, %AST.TypePath{parts: [:Term], lifetimes: [:a]})

  defp parse_rust_type(:u8, [], _aliases), do: type(:u8, path(:u8))
  defp parse_rust_type(:u16, [], _aliases), do: type(:u16, path(:u16))
  defp parse_rust_type(:u32, [], _aliases), do: type(:u32, path(:u32))
  defp parse_rust_type(:u64, [], _aliases), do: type(:u64, path(:u64))
  defp parse_rust_type(:usize, [], _aliases), do: type(:usize, path(:usize))
  defp parse_rust_type(:unit, [], _aliases), do: type(:unit, %AST.TypeUnit{})

  defp parse_rust_type(:path, [parts], _aliases), do: type(:type, spec_path!(parts, nil))
  defp parse_rust_type(:path, [parts, opts], _aliases), do: type(:type, spec_path!(parts, opts))

  defp parse_rust_type(:lifetime, [name], _aliases),
    do: type(:lifetime, {:raw, "'#{spec_path_part!(name)}"})

  defp parse_rust_type(:slice, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:slice, {:raw, "&[#{inner.rust}]"})
  end

  defp parse_rust_type(:raw, [type], _aliases), do: type(:type, raw_type!(type))

  defp parse_rust_type(:ref, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:ref, %AST.TypeRef{inner: inner.ast})
  end

  defp parse_rust_type(:mut_ref, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:mut_ref, %AST.TypeRef{inner: inner.ast, mutable: true})
  end

  defp parse_rust_type(:option, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:option, %AST.TypeOption{inner: inner.ast})
  end

  defp parse_rust_type(:vec, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:vec, %AST.TypeVec{inner: inner.ast})
  end

  defp parse_rust_type(:result, [ok, error], aliases) do
    ok = parse(ok, aliases)
    error = parse(error, aliases)
    type(:result, %AST.TypeResult{ok: ok.ast, error: error.ast})
  end

  defp parse_rust_type(:nif_result, [inner], aliases) do
    inner = parse(inner, aliases)
    type(:nif_result, %AST.TypeNifResult{inner: inner.ast})
  end

  defp parse_rust_type(function, args, aliases) do
    type(:type, %AST.TypePath{
      parts: [function],
      generics: Enum.map(args, &parse(&1, aliases).ast)
    })
  end

  defp parse_external_type({:__aliases__, _, parts}, :t, args, aliases) do
    type(:type, external_type_path(parts, args, aliases), external_type_meta(parts, :t, args))
  end

  defp parse_external_type({:__aliases__, _, parts}, function, args, aliases) do
    type =
      case args do
        [] ->
          %AST.TypePath{parts: external_type_parts(parts) ++ [function]}

        args ->
          %AST.TypePath{
            parts: external_type_parts(parts) ++ [function],
            lifetimes: Enum.flat_map(args, &external_type_lifetimes!/1),
            generics: Enum.flat_map(args, &external_type_generics(&1, aliases))
          }
      end

    type(:type, type, external_type_meta(parts, function, args))
  end

  defp parse_external_type(_module, function, _args, _aliases), do: type(:type, path(function))

  defp spec_path!({:__block__, _, [parts]}, opts), do: spec_path!(parts, opts)

  defp spec_path!(parts, opts) when is_tuple(parts) do
    %AST.TypePath{
      parts: parts |> Tuple.to_list() |> Enum.map(&spec_path_part!/1),
      lifetimes: spec_path_lifetimes!(opts)
    }
  end

  defp spec_path!(part, opts) when is_atom(part), do: spec_path!({part}, opts)

  defp spec_path!(other, _opts) do
    raise ArgumentError, "expected R.path parts tuple, got: #{Macro.to_string(other)}"
  end

  defp spec_path_lifetimes!(nil), do: []

  defp spec_path_lifetimes!({{:., _, [module, :lifetime]}, _, [name]}) do
    if type_module?(module), do: [spec_path_part!(name)], else: []
  end

  defp spec_path_lifetimes!(other) do
    raise ArgumentError,
          "expected R.path option such as R.lifetime(:a), got: #{Macro.to_string(other)}"
  end

  defp spec_path_part!(part) when is_atom(part), do: part
  defp spec_path_part!(part) when is_binary(part), do: String.to_atom(part)

  defp spec_path_part!(other) do
    raise ArgumentError,
          "expected R.path part to be an atom or string, got: #{Macro.to_string(other)}"
  end

  defp raw_type!({:__block__, _, [type]}), do: raw_type!(type)
  defp raw_type!(type) when is_atom(type), do: {:raw, Atom.to_string(type)}

  defp raw_type!(other) do
    raise ArgumentError, "expected R.raw atom marker, got: #{Macro.to_string(other)}"
  end

  defp external_type_path(parts, args, aliases) do
    %AST.TypePath{
      parts: external_type_parts(parts),
      lifetimes: Enum.flat_map(args, &external_type_lifetimes!/1),
      generics: Enum.flat_map(args, &external_type_generics(&1, aliases))
    }
  end

  defp external_type_meta(parts, function, args) do
    %{
      elixir_module: Module.concat(parts),
      elixir_type: function,
      elixir_args: args
    }
  end

  defp external_type_parts([part]), do: [part]
  defp external_type_parts([:"Elixir" | parts]), do: [List.last(parts)]
  defp external_type_parts([:RustQ | parts]), do: [List.last(parts)]

  defp external_type_parts(parts) do
    {modules, [type]} = Enum.split(parts, -1)
    Enum.map(modules, &rust_module_part/1) ++ [type]
  end

  defp external_type_lifetimes!({{:., _, [module, :lifetime]}, _, [name]}) do
    if type_module?(module), do: [spec_path_part!(name)], else: []
  end

  defp external_type_lifetimes!(_arg), do: []

  defp external_type_generics({{:., _, [module, :lifetime]}, _, [_name]}, _aliases) do
    if type_module?(module), do: [], else: raise(ArgumentError, "unsupported lifetime marker")
  end

  defp external_type_generics(arg, aliases), do: [parse(arg, aliases).ast]

  defp rust_module_part(part) when is_atom(part),
    do: part |> Atom.to_string() |> Macro.underscore() |> String.to_atom()

  defp rust_module_part(part) when is_binary(part), do: Macro.underscore(part)

  defp tuple_type(tuple_types) do
    rendered = tuple_types |> Enum.map(& &1.rust) |> Enum.join(", ")
    type(:tuple, {:raw, "(#{rendered})"}, %{elements: tuple_types})
  end

  defp struct_type?({:%, _, [{:__aliases__, _, _parts}, {:%{}, _, fields}]}) when is_list(fields),
    do: true

  defp struct_type?(_ast), do: false

  defp struct_type({:%, _, [{:__aliases__, _, parts}, {:%{}, _, fields}]}) do
    rust_name = parts |> List.last() |> to_string()

    fields =
      Enum.map(fields, fn {name, ast} ->
        {name, parse(ast, %{}), :required}
      end)

    {rust_name, fields}
  end

  defp map_type?({:%{}, _, fields}) when is_list(fields), do: true
  defp map_type?(_ast), do: false

  defp map_fields({:%{}, _, fields}, raw, aliases) do
    Enum.map_reduce(fields, aliases, fn
      {{:required, _, [name]}, ast}, aliases ->
        {type, aliases} = parse_alias_type(ast, raw, aliases)
        {{name, type, :required}, aliases}

      {{:optional, _, [name]}, ast}, aliases ->
        {type, aliases} = parse_alias_type(ast, raw, aliases)
        {{name, type, :optional}, aliases}
    end)
  end

  defp union_members({:|, _, [left, right]}), do: union_members(left) ++ union_members(right)
  defp union_members(other), do: [other]

  defp atom_union?(ast), do: ast |> union_members() |> Enum.all?(&is_atom/1)

  defp option_union?(ast),
    do:
      (
        members = union_members(ast)
        nil in members and length(members) == 2
      )

  defp option_members(ast),
    do:
      (
        members = union_members(ast)
        [nil, Enum.find(members, &(&1 != nil))]
      )

  defp result_union?(ast) do
    members = union_members(ast)

    length(members) == 2 and Enum.any?(members, &match?({:ok, _}, &1)) and
      Enum.any?(members, &match?({:error, _}, &1))
  end

  defp tuple_union?({:|, _, _} = ast, raw, aliases),
    do: ast |> union_members() |> Enum.all?(&tagged_tuple?(&1, raw, aliases))

  defp tuple_union?(_ast, _raw, _aliases), do: false

  defp tagged_tuple?({name, _, args}, raw, aliases) when is_atom(name) and is_list(args) do
    {type, _aliases} = parse_alias_type({name, [], args}, raw, aliases)
    type.kind == :struct
  rescue
    _error -> false
  end

  defp tagged_tuple?(_other, _raw, _aliases), do: false

  defp tuple_variants(ast, raw, aliases) do
    ast
    |> union_members()
    |> Enum.map_reduce(aliases, &tuple_variant(&1, raw, &2))
  end

  defp tuple_variant({name, _, args}, raw, aliases) when is_atom(name) and is_list(args) do
    {type, aliases} = parse_alias_type({name, [], args}, raw, aliases)
    {{String.to_atom(type.meta.rust_name), [type]}, aliases}
  end

  defp result_members(ast) do
    members = union_members(ast)
    {:ok, ok} = Enum.find(members, &match?({:ok, _}, &1))
    {:error, error} = Enum.find(members, &match?({:error, _}, &1))
    {ok, error}
  end

  defp path(part), do: %AST.TypePath{parts: [part]}

  defp type(kind, ast, meta \\ %{}) do
    %__MODULE__{
      kind: kind,
      ast: ast,
      rust: ast |> RustQ.Rust.AST.Render.render_type() |> IO.iodata_to_binary(),
      meta: meta
    }
  end
end
