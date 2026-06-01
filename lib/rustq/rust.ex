defmodule RustQ.Rust do
  @moduledoc """
  Elixir-friendly builders for Rust fragments used with `RustQ.splice/3`.
  """

  alias RustQ.Rust.Const
  alias RustQ.Rust.EnumDecl
  alias RustQ.Rust.Field
  alias RustQ.Rust.Fragment
  alias RustQ.Rust.Function
  alias RustQ.Rust.Impl
  alias RustQ.Rust.ModDecl
  alias RustQ.Rust.Struct
  alias RustQ.Rust.TypeAlias
  alias RustQ.Rust.Use

  @type rust_type :: atom() | String.t() | tuple() | [atom() | String.t()]

  @spec unquote(:use)(term(), keyword()) :: Use.t()
  def unquote(:use)(path, opts \\ []) do
    %Use{path: path, vis: Keyword.get(opts, :vis)}
  end

  @spec raw(iodata()) :: Fragment.t()
  def raw(code), do: %Fragment{kind: :raw, code: code}

  @spec expr(iodata()) :: Fragment.t()
  def expr(code), do: %Fragment{kind: :expr, code: code}

  @spec stmt(iodata()) :: Fragment.t()
  def stmt(code), do: %Fragment{kind: :stmt, code: code}

  @spec param(atom() | String.t(), rust_type()) :: Fragment.t()
  def param(name, type), do: %Fragment{kind: :arg, code: [ident(name), ": ", type(type)]}

  @spec unquote(:item)(iodata()) :: Fragment.t()
  def unquote(:item)(code), do: %Fragment{kind: :item, code: code}

  @spec impl_item(iodata()) :: Fragment.t()
  def impl_item(code), do: %Fragment{kind: :impl_item, code: code}

  @spec arm(iodata()) :: Fragment.t()
  def arm(code), do: %Fragment{kind: :arm, code: code}

  @spec arm(iodata(), iodata()) :: Fragment.t()
  def arm(pattern, body), do: arm([pattern, " => ", body, ","])

  @spec pub(term()) :: term()
  def pub(item), do: vis(item, :pub)

  @spec vis(term(), atom() | String.t() | nil) :: term()
  def vis(%{__struct__: module} = item, visibility)
      when module in [Use, Field, Function, Struct, EnumDecl, ModDecl, Const, TypeAlias] do
    %{item | vis: visibility}
  end

  @spec attr(term(), term()) :: term()
  def attr(%{attrs: attrs} = item, attr), do: %{item | attrs: attrs ++ [attr]}

  @spec derive(Struct.t() | EnumDecl.t(), atom() | String.t() | [atom() | String.t()]) ::
          Struct.t() | EnumDecl.t()
  def derive(%{attrs: attrs} = item, values),
    do: %{item | attrs: [derive_attr(List.wrap(values)) | attrs]}

  @spec field(Struct.t(), atom() | String.t(), rust_type(), keyword()) :: Struct.t()
  def field(%Struct{} = item, name, type, opts) do
    %{item | fields: item.fields ++ [field(name, type, opts)]}
  end

  @spec fields(Struct.t(), [term()]) :: Struct.t()
  def fields(%Struct{} = item, fields), do: %{item | fields: item.fields ++ fields}

  @spec field(atom() | String.t(), rust_type()) :: Field.t()
  def field(name, type), do: field(name, type, [])

  @spec field(atom() | String.t(), rust_type(), keyword()) :: Field.t()
  def field(name, type, opts) do
    %Field{
      name: name,
      type: type,
      attrs: Keyword.get(opts, :attrs, []),
      vis: Keyword.get(opts, :vis)
    }
  end

  @spec fn_(atom() | String.t(), keyword()) :: Function.t()
  def fn_(name, opts \\ []) do
    %Function{
      name: name,
      args: Keyword.get(opts, :args, []),
      attrs: Keyword.get(opts, :attrs, []),
      body: Keyword.get(opts, :body, ""),
      returns: Keyword.get(opts, :returns),
      vis: Keyword.get(opts, :vis),
      generics: function_generics(opts),
      where: Keyword.get(opts, :where, [])
    }
  end

  @doc """
  Alias for `fn_/2`, callable as `RustQ.Rust.fn(...)`.
  """
  def unquote(:fn)(name, opts \\ []), do: fn_(name, opts)

  @spec arg(Function.t(), term()) :: Function.t()
  def arg(%Function{} = function, arg), do: %{function | args: function.args ++ [arg]}

  @spec arg(atom() | String.t(), rust_type()) :: Fragment.t()
  def arg(name, type), do: param(name, type)

  @spec arg(Function.t(), atom() | String.t(), rust_type(), keyword()) :: Function.t()
  def arg(%Function{} = function, name, type, opts \\ []) do
    arg(function, {name, type, opts})
  end

  @spec args(Function.t(), [term()]) :: Function.t()
  def args(%Function{} = function, args), do: %{function | args: function.args ++ args}

  @spec returns(Function.t(), rust_type()) :: Function.t()
  def returns(%Function{} = function, type), do: %{function | returns: type}

  @spec body(Function.t(), iodata()) :: Function.t()
  def body(%Function{} = function, body), do: %{function | body: body}

  @spec struct(atom() | String.t(), keyword()) :: Struct.t()
  def struct(name, opts \\ []) do
    %Struct{
      name: name,
      attrs: attrs_with_derive(opts),
      fields: Keyword.get(opts, :fields, []),
      vis: Keyword.get(opts, :vis)
    }
  end

  @spec enum(atom() | String.t(), keyword()) :: EnumDecl.t()
  def enum(name, opts \\ []) do
    %EnumDecl{
      name: name,
      attrs: attrs_with_derive(opts),
      variants: Keyword.get(opts, :variants, []),
      vis: Keyword.get(opts, :vis)
    }
  end

  @spec unquote(:mod)(atom() | String.t(), keyword()) :: ModDecl.t()
  def unquote(:mod)(name, opts \\ []) do
    %ModDecl{
      name: name,
      attrs: Keyword.get(opts, :attrs, []),
      items: Keyword.get(opts, :items, []),
      vis: Keyword.get(opts, :vis)
    }
  end

  @spec const(atom() | String.t(), rust_type(), term(), keyword()) :: Const.t()
  def const(name, type, value, opts \\ []) do
    %Const{
      name: name,
      type: type,
      value: value,
      attrs: Keyword.get(opts, :attrs, []),
      vis: Keyword.get(opts, :vis)
    }
  end

  @spec type_alias(atom() | String.t(), rust_type(), keyword()) :: TypeAlias.t()
  def type_alias(name, type, opts \\ []) do
    %TypeAlias{
      name: name,
      type: type,
      attrs: Keyword.get(opts, :attrs, []),
      vis: Keyword.get(opts, :vis)
    }
  end

  @spec variant(EnumDecl.t(), term()) :: EnumDecl.t()
  def variant(%EnumDecl{} = item, variant), do: %{item | variants: item.variants ++ [variant]}

  @spec variants(EnumDecl.t(), [term()]) :: EnumDecl.t()
  def variants(%EnumDecl{} = item, variants), do: %{item | variants: item.variants ++ variants}

  @spec impl(rust_type(), keyword()) :: Impl.t()
  def impl(target, opts \\ []) do
    %Impl{target: target, items: Keyword.get(opts, :items, []), trait: Keyword.get(opts, :trait)}
  end

  @spec item(Impl.t() | ModDecl.t(), term()) :: Impl.t() | ModDecl.t()
  def item(%Impl{} = impl, item), do: %{impl | items: impl.items ++ [item]}
  def item(%ModDecl{} = mod, item), do: %{mod | items: mod.items ++ [item]}

  @spec items(Impl.t() | ModDecl.t(), [term()]) :: Impl.t() | ModDecl.t()
  def items(%Impl{} = impl, items), do: %{impl | items: impl.items ++ items}
  def items(%ModDecl{} = mod, items), do: %{mod | items: mod.items ++ items}

  @spec trait(Impl.t(), rust_type()) :: Impl.t()
  def trait(%Impl{} = impl, trait), do: %{impl | trait: trait}

  @spec to_fragment(term()) :: String.t()
  def to_fragment(%Use{} = item) do
    [visibility(item.vis), "use ", path(item.path), ";"]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%Field{} = field) do
    [attrs(field.attrs), visibility(field.vis), ident(field.name), ": ", type(field.type), ","]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%Function{} = function) do
    args = Enum.map_join(function.args, ", ", &arg/1)
    returns = if function.returns, do: [" -> ", type(function.returns)], else: []

    [
      attrs(function.attrs),
      visibility(function.vis),
      "fn ",
      ident(function.name),
      generics(function.generics),
      "(",
      args,
      ")",
      returns,
      where_clause(function.where),
      " {\n",
      function.body,
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%Struct{} = item) do
    fields = item.fields |> Enum.map(&to_fragment/1) |> Enum.intersperse("\n")

    [
      attrs(item.attrs),
      visibility(item.vis),
      "struct ",
      ident(item.name),
      " {\n",
      fields,
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%EnumDecl{} = item) do
    variants = item.variants |> Enum.map(&variant/1) |> Enum.intersperse("\n")

    [
      attrs(item.attrs),
      visibility(item.vis),
      "enum ",
      ident(item.name),
      " {\n",
      variants,
      "\n}"
    ]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%Impl{} = item) do
    items = item.items |> Enum.map(&to_fragment/1) |> Enum.intersperse("\n")
    target = type(item.target)

    header =
      if item.trait, do: ["impl ", type(item.trait), " for ", target], else: ["impl ", target]

    [header, " {\n", items, "\n}"]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%ModDecl{} = item) do
    items = item.items |> Enum.map(&to_fragment/1) |> Enum.intersperse("\n")

    [attrs(item.attrs), visibility(item.vis), "mod ", ident(item.name), " {\n", items, "\n}"]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%Const{} = item) do
    [
      attrs(item.attrs),
      visibility(item.vis),
      "const ",
      ident(item.name),
      ": ",
      type(item.type),
      " = ",
      value(item.value),
      ";"
    ]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%TypeAlias{} = item) do
    [
      attrs(item.attrs),
      visibility(item.vis),
      "type ",
      ident(item.name),
      " = ",
      type(item.type),
      ";"
    ]
    |> IO.iodata_to_binary()
  end

  def to_fragment(%Fragment{} = fragment), do: IO.iodata_to_binary(fragment.code)
  def to_fragment(value) when is_binary(value), do: value
  def to_fragment(value) when is_list(value), do: IO.iodata_to_binary(value)

  @spec literal(term()) :: String.t()
  def literal(value) when is_binary(value), do: inspect(value)
  def literal(value) when is_boolean(value), do: to_string(value)
  def literal(nil), do: "None"
  def literal(value) when is_integer(value) or is_float(value), do: to_string(value)

  @spec type(atom() | String.t(), keyword() | [rust_type()]) :: String.t()
  def type(name, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      generic_type(name, Keyword.get(opts, :generics, []), Keyword.get(opts, :lifetime))
    else
      generic_type(name, opts, nil)
    end
  end

  @spec ref(rust_type(), keyword()) :: String.t()
  def ref(value, opts \\ []) do
    mut = if Keyword.get(opts, :mut), do: "mut ", else: ""
    lifetime = if lifetime = Keyword.get(opts, :lifetime), do: "'#{lifetime} ", else: ""
    "&#{lifetime}#{mut}#{type(value)}"
  end

  @spec static_slice(rust_type()) :: String.t()
  def static_slice(value), do: ref({:slice, value}, lifetime: :static)

  @spec use_many([term()], keyword()) :: [Use.t()]
  def use_many(paths, opts \\ []) do
    Enum.map(paths, &__MODULE__.use(&1, opts))
  end

  @spec prelude(atom()) :: [Use.t()]
  def prelude(:rustler_resource) do
    use_many([
      {:path, [:std, :sync, :OnceLock]},
      {:path, [:rustler, :Env]},
      {:path, [:rustler, :Encoder]},
      {:path, [:rustler, :NifResult]},
      {:path, [:rustler, :ResourceArc]},
      {:path, [:rustler, :Term]}
    ])
  end

  @spec type(rust_type()) :: String.t()
  def type(value) when is_binary(value), do: value
  def type(value) when is_atom(value), do: ident(value)

  def type({:ref, opts}) when is_list(opts) do
    mut = if Keyword.get(opts, :mut), do: "mut ", else: ""
    lifetime = if lifetime = Keyword.get(opts, :lifetime), do: "'#{lifetime} ", else: ""
    "&#{lifetime}#{mut}#{type(Keyword.fetch!(opts, :type))}"
  end

  def type({:ref, value}), do: "&#{type(value)}"
  def type({:option, value}), do: "Option<#{type(value)}>"
  def type({:result, ok, error}), do: "Result<#{type(ok)}, #{type(error)}>"
  def type({:vec, value}), do: "Vec<#{type(value)}>"
  def type({:box, value}), do: "Box<#{type(value)}>"
  def type({:dyn, value}), do: "dyn #{type(value)}"
  def type({:tuple, values}), do: "(#{Enum.map_join(values, ", ", &type/1)})"
  def type({:array, value, size}), do: "[#{type(value)}; #{size}]"
  def type({:slice, value}), do: "[#{type(value)}]"
  def type({:raw, value}), do: IO.iodata_to_binary(value)
  def type({:path, parts}), do: path(parts)

  def type({:path, parts, generics}),
    do: "#{path(parts)}<#{Enum.map_join(generics, ", ", &type/1)}>"

  def type(parts) when is_list(parts), do: path(parts)

  defp function_generics(opts) do
    opts
    |> Keyword.get(:generics, [])
    |> List.wrap()
    |> Kernel.++(opts |> Keyword.get(:lifetimes, []) |> List.wrap() |> Enum.map(&"'#{&1}"))
    |> then(fn generics ->
      case Keyword.get(opts, :lifetime) do
        nil -> generics
        lifetime -> ["'#{lifetime}" | generics]
      end
    end)
  end

  defp generic_type(name, generics, nil) do
    case List.wrap(generics) do
      [] -> type(name)
      generics -> "#{type(name)}<#{Enum.map_join(generics, ", ", &type/1)}>"
    end
  end

  defp generic_type(name, generics, lifetime) do
    generic_type(name, ["'#{lifetime}" | List.wrap(generics)], nil)
  end

  defp generics([]), do: []
  defp generics(values), do: ["<", Enum.map_join(values, ", ", &type/1), ">"]

  defp where_clause([]), do: []

  defp where_clause(values) do
    ["\nwhere\n", values |> List.wrap() |> Enum.map_join(",\n", &["    ", &1])]
  end

  defp attrs_with_derive(opts) do
    derive = Keyword.get(opts, :derive, [])
    attrs = Keyword.get(opts, :attrs, [])

    case List.wrap(derive) do
      [] -> attrs
      values -> [derive_attr(values) | attrs]
    end
  end

  defp derive_attr(values),
    do: ["derive(", values |> Enum.map(&type/1) |> Enum.intersperse(", "), ")"]

  defp variant(name) when is_atom(name) or is_binary(name), do: [ident(name), ","]

  defp variant({name, opts}) when is_list(opts) do
    cond do
      fields = Keyword.get(opts, :fields) ->
        [ident(name), " { ", enum_fields(fields), " },"]

      tuple = Keyword.get(opts, :tuple) ->
        [ident(name), "(", Enum.map_join(tuple, ", ", &type/1), "),"]

      true ->
        [ident(name), ","]
    end
  end

  defp enum_fields(fields) do
    fields
    |> Enum.map(fn
      %Field{} = field -> [ident(field.name), ": ", type(field.type)]
      {name, type} -> [ident(name), ": ", type(type)]
    end)
    |> Enum.intersperse(", ")
  end

  defp value(%Fragment{} = fragment), do: to_fragment(fragment)
  defp value({:literal, literal}), do: literal(literal)
  defp value(value) when is_binary(value), do: value
  defp value(value) when is_list(value), do: IO.iodata_to_binary(value)

  defp arg(:self), do: "self"
  defp arg(:self_ref), do: "&self"
  defp arg(:self_mut), do: "&mut self"
  defp arg({:self_ref, opts}), do: "&'#{Keyword.fetch!(opts, :lifetime)} self"
  defp arg({name, type}), do: "#{ident(name)}: #{type(type)}"

  defp arg({name, type, opts}) do
    mut = if Keyword.get(opts, :mut), do: "mut ", else: ""
    "#{mut}#{ident(name)}: #{type(type)}"
  end

  defp attrs(attrs) do
    attrs
    |> List.wrap()
    |> Enum.map(fn attr -> ["#[", attr(attr), "]\n"] end)
  end

  defp attr(value) when is_atom(value), do: ident(value)
  defp attr(value) when is_binary(value), do: value
  defp attr(value) when is_list(value), do: value

  defp visibility(nil), do: []
  defp visibility(:pub), do: "pub "
  defp visibility(:crate), do: "pub(crate) "
  defp visibility(value) when is_binary(value), do: [value, " "]

  defp path(parts), do: Enum.map_join(List.wrap(parts), "::", &ident/1)
  defp ident(value) when is_atom(value), do: Atom.to_string(value)
  defp ident(value) when is_binary(value), do: value
end
