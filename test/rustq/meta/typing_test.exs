defmodule RustQ.Meta.TypingTest do
  use ExUnit.Case, async: true

  alias RustQ.Binding.Callable
  alias RustQ.Meta.Type
  alias RustQ.Meta.Typing
  alias RustQ.Rust.AST

  defp type(kind, rust) do
    %Type{kind: kind, rust: rust, ast: %AST.TypePath{parts: [String.to_atom(rust)]}}
  end

  test "synthesizes variables and local callable return types from explicit env" do
    path = type(:type, "Path")

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path.ast},
      meta: %{inner: path}
    }

    env =
      Typing.env(
        vars: %{path: path},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert Typing.synth(quote(do: path), env) == path
    assert Typing.synth(quote(do: maybe_path()), env) == option_path
  end

  test "checks propagation, option wrapping, and borrow coercions" do
    color = type(:type, "Color")

    nif_color = %Type{
      kind: :nif_result,
      rust: "NifResult<Color>",
      ast: %AST.TypeNifResult{inner: color.ast},
      meta: %{inner: color}
    }

    option_color = %Type{
      kind: :option,
      rust: "Option<Color>",
      ast: %AST.TypeOption{inner: color.ast},
      meta: %{inner: color}
    }

    ref_color = %Type{
      kind: :ref,
      rust: "&Color",
      ast: %AST.TypeRef{inner: color.ast},
      meta: %{inner: color}
    }

    env =
      Typing.env(
        vars: %{color: color},
        callables: [%Callable{name: "decode", kind: :function, args: [], returns: nif_color}]
      )

    assert %Typing.Check{coercion: :propagate} = Typing.check(quote(do: decode()), color, env)
    assert %Typing.Check{coercion: :some} = Typing.check(quote(do: color), option_color, env)
    assert %Typing.Check{coercion: :borrow} = Typing.check(quote(do: color), ref_color, env)
  end

  test "infers let expectations from vars and tuple-return calls" do
    left = type(:u32, "u32")
    right = type(:u32, "u32")

    tuple = %Type{
      kind: :tuple,
      rust: "(u32, u32)",
      ast: %AST.TypeRaw{source: "(u32, u32)"},
      meta: %{elements: [left, right]}
    }

    result_tuple = %Type{
      kind: :nif_result,
      rust: "NifResult<(u32, u32)>",
      ast: %AST.TypeNifResult{inner: tuple.ast},
      meta: %{inner: tuple}
    }

    env =
      Typing.env(
        vars: %{known: left},
        callables: [%Callable{name: "pair", kind: :function, args: [], returns: result_tuple}]
      )

    assert Typing.expected_for_let(quote(do: known), quote(do: ignored()), env) == left
    assert Typing.expected_for_let(quote(do: {a, b}), quote(do: pair()), env) == tuple
    assert Typing.expected_for_let(quote(do: unknown), quote(do: ignored()), env) == nil
  end

  test "synthesizes cast target types" do
    assert %Type{kind: :u8, rust: "u8"} =
             Typing.synth(quote(do: cast(value, RustQ.Type.u8())), Typing.env())
  end

  test "returns struct field expectations" do
    x = type(:f32, "f32")
    y = type(:f32, "f32")

    point = %Type{
      kind: :struct,
      rust: "Point",
      ast: %AST.TypePath{parts: [:Point]},
      meta: %{fields: [{:x, x, :required}, {:y, y, :required}]}
    }

    assert Typing.struct_field_type(point, :x) == x
    assert Typing.struct_field_type(point, :missing) == nil
  end

  test "delegates downstream let inference through explicit env" do
    mode = type(:type, "Mode")

    env =
      Typing.env(
        callables: [
          %Callable{
            name: "consume",
            kind: :function,
            args: [%{name: "mode", type: mode}],
            returns: nil
          }
        ]
      )

    inferred =
      Typing.infer_downstream_let_types(
        [
          quote(do: mode = decode()),
          quote(do: consume(mode))
        ],
        env,
        %{
          local_argument_types: fn
            :consume, 1 -> [mode]
            _name, _arity -> nil
          end
        }
      )

    assert inferred == %{mode: mode}
  end

  test "checks propagation through impl Into option expectations" do
    image_filter = type(:type, "ImageFilter")

    option_filter = %Type{
      kind: :option,
      rust: "Option<ImageFilter>",
      ast: %AST.TypeOption{inner: image_filter.ast},
      meta: %{inner: image_filter}
    }

    nif_option_filter = %Type{
      kind: :nif_result,
      rust: "NifResult<Option<ImageFilter>>",
      ast: %AST.TypeNifResult{inner: option_filter.ast},
      meta: %{inner: option_filter}
    }

    into_option_filter = %Type{
      kind: :impl_trait,
      rust: "impl Into<Option<ImageFilter>>",
      ast: %AST.TypeRaw{source: "impl Into<Option<ImageFilter>>"},
      meta: %{
        traits: [
          %Type{
            kind: :type,
            rust: "Into<Option<ImageFilter>>",
            ast: %AST.TypePath{parts: [:Into]},
            meta: %{syn_name: "Into", args: [option_filter]}
          }
        ]
      }
    }

    env =
      Typing.env(
        callables: [
          %Callable{name: "decode_filter", kind: :function, args: [], returns: nif_option_filter}
        ]
      )

    assert %Typing.Check{coercion: :propagate} =
             Typing.check(quote(do: decode_filter()), into_option_filter, env)
  end

  test "synthesizes method calls through receiver type" do
    paint = type(:type, "Paint")
    color = type(:type, "Color")

    env =
      Typing.env(
        vars: %{paint: paint},
        callables: [
          %Callable{
            name: "color",
            kind: :method,
            target: "Paint",
            args: [%{name: "self", type: paint, syn: nil}],
            returns: color
          }
        ]
      )

    assert Typing.synth(quote(do: paint.color()), env) == color
  end

  test "synthesizes method calls through raw receiver type" do
    decoder = %Type{kind: :raw, rust: "Decoder<'_>", ast: %AST.TypeRaw{source: "Decoder<'_>"}}
    count = type(:u32, "u32")

    env =
      Typing.env(
        vars: %{decoder: decoder},
        callables: [
          %Callable{
            name: "read_var_uint",
            kind: :method,
            target: "Decoder",
            args: [%{name: "self", type: decoder, syn: nil}],
            returns: count
          }
        ]
      )

    assert Typing.synth(quote(do: decoder.read_var_uint()), env) == count
  end

  test "checks exact compatible values without coercion" do
    count = type(:u32, "u32")
    env = Typing.env(vars: %{count: count})

    assert %Typing.Check{type: ^count, coercion: :none} =
             Typing.check(quote(do: count), count, env)
  end
end
