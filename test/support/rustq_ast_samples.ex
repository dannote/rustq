defmodule RustQ.ASTSamples do
  @moduledoc false

  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.Render
  alias RustQ.Rust.AST.Builder, as: A

  require A

  def all do
    RustQ.Rust.AST.Schema.nodes()
    |> Map.new(fn node -> {node.name, sample_for(node.name)} end)
  end

  def validate_rendered?(name, ast, source) when is_binary(source) do
    source =~ base_fragment(ast) and source =~ semantic_fragment(name)
  end

  defp base_fragment(%AST.Use{parts: parts}) when is_list(parts),
    do: "use #{Enum.map_join(parts, "::", &to_string/1)};"

  defp base_fragment(%AST.Use{group: {base, names}}) do
    "use #{Enum.map_join(base, "::", &to_string/1)}::{#{Enum.map_join(names, ", ", &to_string/1)}};"
  end

  defp base_fragment(%AST.Use{tree: tree}), do: "use #{tree};"
  defp base_fragment(%AST.Module{name: name}), do: "mod #{name}"
  defp base_fragment(%AST.MacroItem{source: source}), do: source

  defp base_fragment(%AST.MacroItemCall{path: path}) do
    [RustQ.Rust.AST.Render.render_expr(path), "!"] |> IO.iodata_to_binary()
  end

  defp base_fragment(%AST.Const{name: name}), do: "const #{name}"
  defp base_fragment(%AST.Static{name: name}), do: "static #{name}"
  defp base_fragment(%AST.TypeAlias{name: name}), do: "type #{name}"
  defp base_fragment(%AST.Impl{target: target}), do: "impl #{Render.render_type(target)}"
  defp base_fragment(%AST.Struct{name: name}), do: "struct #{name}"
  defp base_fragment(%AST.Enum{name: name}), do: "enum #{name}"
  defp base_fragment(%AST.Function{name: name}), do: "fn #{name}"

  defp semantic_fragment(:module), do: "mod sample"
  defp semantic_fragment(:macro_item_call), do: "rustler::atoms!"
  defp semantic_fragment(:attribute), do: ~s|#[allow(dead_code)]|
  defp semantic_fragment(:type_alias), do: "type Bytes = Vec<u8>;"
  defp semantic_fragment(:impl), do: "impl Sample"
  defp semantic_fragment(:function_arg), do: "value: u32"
  defp semantic_fragment(:derive), do: "#[derive(Clone, serde::Serialize)]"
  defp semantic_fragment(:struct_field), do: "value: u32"
  defp semantic_fragment(:enum_variant), do: "Unit"
  defp semantic_fragment(:type_path), do: "type_path_VALUE: u32"
  defp semantic_fragment(:type_ref), do: "type_ref_VALUE: &str"
  defp semantic_fragment(:type_option), do: "Option<u32>"
  defp semantic_fragment(:type_result), do: "Result<u32, String>"
  defp semantic_fragment(:type_nif_result), do: "NifResult<u32>"
  defp semantic_fragment(:type_vec), do: "Vec<u8>"
  defp semantic_fragment(:type_unit), do: "type_unit_VALUE: ()"
  defp semantic_fragment(:let), do: "let value = 1i64;"
  defp semantic_fragment(:let_else), do: "let Some(value) = maybe"
  defp semantic_fragment(:assign), do: "value = 2i64;"
  defp semantic_fragment(:expr_stmt), do: "side_effect();"
  defp semantic_fragment(:return), do: "1i64"
  defp semantic_fragment(:early_return), do: "return 1i64;"
  defp semantic_fragment(:if_let), do: "if let Some(value) = maybe"
  defp semantic_fragment(:for), do: "for value in values"
  defp semantic_fragment(:var), do: "value"
  defp semantic_fragment(:path), do: "Sample::VALUE"
  defp semantic_fragment(:field), do: "opts.value"
  defp semantic_fragment(:index), do: "values[0i64]"
  defp semantic_fragment(:range), do: "start..stop"
  defp semantic_fragment(:cast), do: "value as f32"
  defp semantic_fragment(:unary_op), do: "!condition"
  defp semantic_fragment(:path_call), do: "Vec::new::<u8>()"
  defp semantic_fragment(:method_call), do: "term.decode::<Atom>()"
  defp semantic_fragment(:struct_literal), do: "Point { x: 1i64 }"
  defp semantic_fragment(:local_call), do: "make_value()"
  defp semantic_fragment(:ref), do: "&value"
  defp semantic_fragment(:try), do: "fallible()?"
  defp semantic_fragment(:tuple), do: "(1i64, 2i64)"
  defp semantic_fragment(:vec_literal), do: "vec![1i64, 2i64]"
  defp semantic_fragment(:array_literal), do: "[1i64, 2i64]"
  defp semantic_fragment(:closure), do: "|value| value"
  defp semantic_fragment(:literal), do: "1i64"
  defp semantic_fragment(:byte_string), do: ~s|b"ref"|
  defp semantic_fragment(:escape_expr), do: "value.unwrap()"
  defp semantic_fragment(:token_macro), do: "quote!(None)"
  defp semantic_fragment(:macro_call), do: ~s|format!("{}", value)|
  defp semantic_fragment(:atom_value), do: "atoms::ok()"
  defp semantic_fragment(:none), do: "None"
  defp semantic_fragment(:some), do: "Some(1i64)"
  defp semantic_fragment(:ok), do: "Ok(())"
  defp semantic_fragment(:err), do: "Err(rustler::Error::BadArg)"
  defp semantic_fragment(:nif_raise_atom), do: "RaiseAtom"
  defp semantic_fragment(:match), do: "match value"
  defp semantic_fragment(:if), do: "if condition"
  defp semantic_fragment(:binary_op), do: "left == right"
  defp semantic_fragment(:arm), do: "_ =>"
  defp semantic_fragment(:pat_var), do: "value =>"
  defp semantic_fragment(:pat_wildcard), do: "_ =>"
  defp semantic_fragment(:pat_path), do: "Option::None =>"
  defp semantic_fragment(:pat_literal), do: ~s|"ready" =>|
  defp semantic_fragment(:pat_none), do: "None =>"
  defp semantic_fragment(:pat_some), do: "Some(value) =>"
  defp semantic_fragment(:pat_atom_guard), do: "value if value == atoms::ok()"
  defp semantic_fragment(:pat_tuple), do: "(left, right) =>"
  defp semantic_fragment(:pat_ok), do: "Ok(value) =>"
  defp semantic_fragment(:pat_err), do: "Err(reason) =>"
  defp semantic_fragment(:pat_path_tuple), do: "Event::Click(click) =>"
  defp semantic_fragment(:pat_struct), do: "Click { name: name } =>"
  defp semantic_fragment(_), do: ""

  def sample_for(:use), do: %AST.Use{group: {[:std], [:fmt, :io]}}
  def sample_for(:module), do: %AST.Module{name: :sample, items: [sample_for(:const)]}
  def sample_for(:const), do: %AST.Const{name: :VALUE, type: A.type_path(:u32), expr: A.lit(1)}

  def sample_for(:static),
    do: %AST.Static{
      name: :VALUE_STATIC,
      type: A.type_path(:u32),
      expr: A.lit(1)
    }

  def sample_for(:type_alias),
    do: A.type_alias(:Bytes, A.type_path(:Vec, generics: [A.type_path(:u8)]))

  def sample_for(:macro_item), do: %AST.MacroItem{source: "type Alias = u32;"}
  def sample_for(:macro_item_call), do: A.macro_item_call([:rustler, :atoms], [:ok, :error])

  def sample_for(:impl),
    do: %AST.Impl{
      target: A.type_path(:Sample),
      items: [function_sample(:new, A.struct([:Sample], []), returns: "Self")]
    }

  def sample_for(:function), do: function_sample(:function, A.lit(1), returns: "i64")

  def sample_for(:attribute),
    do:
      function_sample(:attribute_sample, A.lit(1),
        returns: "i64",
        attrs: [A.allow_attr(:dead_code)]
      )

  def sample_for(:function_arg),
    do: %AST.Function{
      name: :function_arg_sample,
      args: [%AST.FunctionArg{name: :value, type: A.type_path(:u32)}],
      returns: "u32",
      body: [A.return(:value)]
    }

  def sample_for(:derive) do
    %AST.Struct{
      name: :DeriveSample,
      derive: [%AST.Derive{paths: [:Clone, [:serde, :Serialize]]}],
      fields: [%AST.StructField{name: :value, type: A.type_path(:u32)}]
    }
  end

  def sample_for(:struct) do
    %AST.Struct{name: :Sample, fields: [%AST.StructField{name: :value, type: A.type_path(:u32)}]}
  end

  def sample_for(:struct_field), do: sample_for(:struct)

  def sample_for(:enum) do
    %AST.Enum{name: :SampleEnum, variants: [%AST.EnumVariant{name: :Unit}]}
  end

  def sample_for(:enum_variant), do: sample_for(:enum)
  def sample_for(:type_path), do: type_sample(:type_path, A.type_path(:u32))
  def sample_for(:type_ref), do: type_sample(:type_ref, %AST.TypeRef{inner: A.type_path(:str)})

  def sample_for(:type_option),
    do: type_sample(:type_option, %AST.TypeOption{inner: A.type_path(:u32)})

  def sample_for(:type_result),
    do:
      type_sample(:type_result, %AST.TypeResult{
        ok: A.type_path(:u32),
        error: A.type_path(:String)
      })

  def sample_for(:type_nif_result),
    do: type_sample(:type_nif_result, %AST.TypeNifResult{inner: A.type_path(:u32)})

  def sample_for(:type_vec), do: type_sample(:type_vec, %AST.TypeVec{inner: A.type_path(:u8)})
  def sample_for(:type_unit), do: type_sample(:type_unit, %AST.TypeUnit{})

  def sample_for(:let),
    do:
      function_sample(:let_sample, %AST.Var{name: :value},
        body: [A.let(:value, A.lit(1)), A.return(:value)],
        returns: "i64"
      )

  def sample_for(:assign),
    do:
      function_sample(:assign_sample, A.var(:value),
        body: [A.let_mut(:value, A.lit(1)), A.assign(:value, A.lit(2)), A.return(:value)],
        returns: "i64"
      )

  def sample_for(:let_else),
    do:
      function_sample(:let_else_sample, A.var(:value),
        body: [
          A.let_else(A.some_pat(:value), :maybe, [A.early_return(A.lit(0))]),
          A.return(:value)
        ],
        returns: "i64"
      )

  def sample_for(:expr_stmt),
    do: function_sample(:expr_stmt, A.call(:side_effect), statement?: true)

  def sample_for(:return), do: function_sample(:return_sample, A.lit(1), returns: "i64")

  def sample_for(:early_return),
    do:
      function_sample(:early_return_sample, A.var(:value),
        body: [A.early_return(A.lit(1)), A.return(A.lit(2))],
        returns: "i64"
      )

  def sample_for(:if_let),
    do:
      function_sample(:if_let_sample, A.ok(),
        body: [
          A.if_let(A.some_pat(:value), :maybe, [A.stmt(A.call(:use_value, [:value]))]),
          A.return(A.ok())
        ],
        returns: "NifResult<()>"
      )

  def sample_for(:for),
    do:
      function_sample(:for_sample, A.ok(),
        body: [
          A.for_(A.pat(:value), :values, [A.stmt(A.call(:use_value, [:value]))]),
          A.return(A.ok())
        ],
        returns: "NifResult<()>"
      )

  def sample_for(:var), do: function_sample(:var_sample, A.var(:value), returns: "i64")

  def sample_for(:path),
    do: function_sample(:path_sample, A.path([:Sample, :VALUE]), returns: "i64")

  def sample_for(:field),
    do:
      function_sample(:field_sample, %AST.Field{receiver: A.var(:opts), field: :value},
        returns: "i64"
      )

  def sample_for(:index),
    do: function_sample(:index_sample, A.index(:values, A.lit(0)), returns: "i64")

  def sample_for(:range),
    do: function_sample(:range_sample, A.range(:start, :stop), returns: "std::ops::Range<i64>")

  def sample_for(:cast), do: function_sample(:cast_sample, A.cast(:value, "f32"), returns: "f32")

  def sample_for(:unary_op),
    do: function_sample(:unary_op_sample, A.not_(:condition), returns: "bool")

  def sample_for(:path_call),
    do:
      function_sample(
        :path_call_sample,
        A.path_call([:Vec, :new], [], generics: [A.type_path(:u8)]),
        returns: "Vec<u8>"
      )

  def sample_for(:method_call),
    do:
      function_sample(
        :method_call_sample,
        A.method(:term, :decode, [], generics: [A.type_path(:Atom)]),
        returns: "NifResult<Atom>"
      )

  def sample_for(:struct_literal),
    do: function_sample(:struct_literal_sample, A.struct([:Point], x: A.lit(1)), returns: "Point")

  def sample_for(:local_call),
    do: function_sample(:local_call_sample, A.call(:make_value), returns: "i64")

  def sample_for(:ref), do: function_sample(:ref_sample, A.ref(:value), returns: "&i64")

  def sample_for(:try),
    do: function_sample(:try_sample, A.try(A.call(:fallible)), returns: "NifResult<()> ")

  def sample_for(:tuple),
    do:
      function_sample(:tuple_sample, %AST.Tuple{values: [A.lit(1), A.lit(2)]},
        returns: "(i64, i64)"
      )

  def sample_for(:vec_literal),
    do: function_sample(:vec_literal_sample, A.vec([A.lit(1), A.lit(2)]), returns: "Vec<i64>")

  def sample_for(:array_literal),
    do: function_sample(:array_literal_sample, A.array([A.lit(1), A.lit(2)]), returns: "[i64; 2]")

  def sample_for(:closure),
    do:
      function_sample(:closure_sample, A.closure([:value], A.var(:value)),
        returns: "impl Fn(i64) -> i64"
      )

  def sample_for(:literal), do: function_sample(:literal_sample, A.lit(1), returns: "i64")

  def sample_for(:byte_string),
    do: function_sample(:byte_string_sample, A.byte_string("ref"), returns: "&'static [u8; 3]")

  def sample_for(:escape_expr),
    do: function_sample(:escape_expr_sample, A.escape_expr("value.unwrap()"), returns: "i64")

  def sample_for(:token_macro),
    do:
      function_sample(:token_macro_sample, A.token_macro(:quote, "None"), returns: "TokenStream")

  def sample_for(:macro_call),
    do:
      function_sample(:macro_call_sample, A.macro_call(:format, [A.lit("{}"), A.var(:value)]),
        args: [value: "i64"],
        returns: "String"
      )

  def sample_for(:atom_value),
    do: function_sample(:atom_value_sample, %AST.AtomValue{name: :ok}, returns: "Atom")

  def sample_for(:none), do: function_sample(:none_sample, A.none(), returns: "Option<i64>")

  def sample_for(:some),
    do: function_sample(:some_sample, A.some(A.lit(1)), returns: "Option<i64>")

  def sample_for(:ok), do: function_sample(:ok_sample, A.ok(), returns: "NifResult<()> ")

  def sample_for(:err),
    do:
      function_sample(:err_sample, A.err(A.path([:rustler, :Error, :BadArg])),
        returns: "NifResult<()> "
      )

  def sample_for(:nif_raise_atom),
    do:
      function_sample(:nif_raise_atom_sample, %AST.NifRaiseAtom{name: :invalid},
        returns: "NifResult<()> "
      )

  def sample_for(:match), do: match_sample(:match_sample, A.wildcard())

  def sample_for(:if),
    do:
      sample_for(:match)
      |> Map.put(:name, :if_sample)
      |> Map.put(:body, [
        A.return(A.if_expr(:condition, [A.return(A.lit(1))], [A.return(A.lit(0))]))
      ])

  def sample_for(:binary_op),
    do: function_sample(:binary_op_sample, A.eq(:left, :right), returns: "bool")

  def sample_for(:arm), do: match_sample(:arm_sample, A.wildcard())
  def sample_for(:pat_var), do: match_sample(:pat_var_sample, A.pat(:value))
  def sample_for(:pat_wildcard), do: match_sample(:pat_wildcard_sample, A.wildcard())
  def sample_for(:pat_path), do: match_sample(:pat_path_sample, A.path_pat(["Option", "None"]))
  def sample_for(:pat_literal), do: match_sample(:pat_literal_sample, A.lit_pat("ready"))
  def sample_for(:pat_none), do: match_sample(:pat_none_sample, A.none_pat())
  def sample_for(:pat_some), do: match_sample(:pat_some_sample, A.some_pat(:value))

  def sample_for(:pat_atom_guard),
    do: match_sample(:pat_atom_guard_sample, %AST.PatAtomGuard{name: :ok}, args: [value: "Atom"])

  def sample_for(:pat_tuple),
    do: match_sample(:pat_tuple_sample, %AST.PatTuple{patterns: [A.pat(:left), A.pat(:right)]})

  def sample_for(:pat_ok), do: match_sample(:pat_ok_sample, A.ok_pat(:value))
  def sample_for(:pat_err), do: match_sample(:pat_err_sample, A.err_pat(:reason))

  def sample_for(:pat_path_tuple),
    do: match_sample(:pat_path_tuple_sample, A.path_tuple_pat([:Event, :Click], [A.pat(:click)]))

  def sample_for(:pat_struct),
    do: match_sample(:pat_struct_sample, A.struct_pat([:Click], name: A.pat(:name)))

  defp type_sample(name, type) do
    %AST.Const{name: String.to_atom("#{name}_VALUE"), type: type, expr: A.lit(0)}
  end

  defp function_sample(name, expr, opts) do
    body = Keyword.get(opts, :body)
    returns = Keyword.get(opts, :returns, "()")

    body =
      cond do
        body -> body
        Keyword.get(opts, :statement?) -> [A.stmt(expr), A.return(%AST.Tuple{values: []})]
        true -> [A.return(expr)]
      end

    %AST.Function{
      name: name,
      args: Keyword.get(opts, :args, []),
      returns: returns,
      body: body,
      attrs: Keyword.get(opts, :attrs, [])
    }
  end

  defp match_sample(name, pattern, opts \\ []) do
    function_sample(name, A.var(:value),
      args: Keyword.get(opts, :args, []),
      returns: "i64",
      body: [
        A.return(%AST.Match{
          expr: A.var(:value),
          arms: [%AST.Arm{pattern: pattern, body: [A.return(A.lit(1))]}]
        })
      ]
    )
  end
end
