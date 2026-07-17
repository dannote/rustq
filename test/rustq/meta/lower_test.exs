defmodule RustQ.Meta.LowerTest do
  use ExUnit.Case, async: true

  alias RustQ.Binding.Callable
  alias RustQ.Meta.GeneratedCase, as: Generated
  alias RustQ.Meta.Lower
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  import RustQ.Meta.LowerCase

  test "lowers ok_or bang as option to result propagation" do
    statements =
      Lower.quoted_body(
        quote do
          ok_or!(paint.shader(), badarg())
        end,
        %Type{
          kind: :nif_result,
          rust: "NifResult<Shader>",
          ast: %AST.TypeNifResult{inner: %AST.TypePath{parts: [:Shader]}}
        },
        %{paint: %Type{kind: :type, rust: "Paint", ast: %AST.TypePath{parts: [:Paint]}}}
      )

    assert [
             %AST.Return{
               expr: %AST.Try{
                 expr: %AST.MethodCall{
                   method: :ok_or,
                   receiver: %AST.MethodCall{method: :shader},
                   args: [%AST.Path{parts: [:rustler, :Error, :BadArg]}]
                 }
               }
             }
           ] = statements
  end

  test "infers return-position propagation from callable metadata" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(quote(do: maybe_path()), path_type, %{},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert [
             %AST.Return{
               expr: %AST.Try{expr: %AST.LocalCall{name: :maybe_path, args: []}}
             }
           ] =
             statements
  end

  test "infers return-position propagation for remote callable metadata" do
    mode_type = %Type{kind: :type, rust: "Mode", ast: %AST.TypePath{parts: [:Mode]}}

    result_mode = %Type{
      kind: :result,
      rust: "Result<Mode, Error>",
      ast: %AST.TypeResult{ok: mode_type.ast, error: %AST.TypePath{parts: [:Error]}},
      meta: %{ok: mode_type}
    }

    statements =
      Lower.quoted_body(
        quote(do: Generated.decode_mode(atom)),
        mode_type,
        %{atom: %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}}},
        callables: [
          %Callable{
            name: "decode_mode",
            kind: :function,
            target: "Generated",
            args: [
              %{
                name: "atom",
                type: %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}},
                syn: nil
              }
            ],
            returns: result_mode
          }
        ]
      )

    assert [
             %AST.Return{
               expr: %AST.Try{
                 expr: %AST.PathCall{path: %AST.Path{parts: [:Generated, :decode_mode]}}
               }
             }
           ] =
             statements
  end

  test "infers propagation inside ref wrapper arguments" do
    matrix_type = %Type{kind: :type, rust: "Matrix", ast: %AST.TypePath{parts: [:Matrix]}}

    matrix_ref_type = %Type{
      kind: :ref,
      rust: "&Matrix",
      ast: %AST.TypeRef{inner: matrix_type.ast},
      meta: %{inner: matrix_type}
    }

    nif_matrix_type = %Type{
      kind: :nif_result,
      rust: "NifResult<Matrix>",
      ast: %AST.TypeNifResult{inner: matrix_type.ast},
      meta: %{inner: matrix_type}
    }

    term_type = %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}}

    statements =
      Lower.quoted_body(
        quote do
          matrix_transform(ref(matrix_from_term(term)))
          :ok
        end,
        unit_type(),
        %{term: term_type},
        callables: [
          %Callable{
            name: "matrix_from_term",
            kind: :function,
            args: [%{name: "term", type: term_type, syn: nil}],
            returns: nif_matrix_type
          },
          %Callable{
            name: "matrix_transform",
            kind: :function,
            args: [%{name: "matrix", type: matrix_ref_type, syn: nil}],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.LocalCall{
                 name: :matrix_transform,
                 args: [%AST.Ref{expr: %AST.Try{expr: %AST.LocalCall{name: :matrix_from_term}}}]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers propagation through impl Into option arguments from plain values" do
    tile_mode_type = %Type{
      kind: :type,
      rust: "TileMode",
      ast: %AST.TypePath{parts: [:TileMode]}
    }

    option_tile_mode_type = %Type{
      kind: :option,
      rust: "Option<TileMode>",
      ast: %AST.TypeOption{inner: tile_mode_type.ast},
      meta: %{inner: tile_mode_type}
    }

    nif_tile_mode_type = %Type{
      kind: :nif_result,
      rust: "NifResult<TileMode>",
      ast: %AST.TypeNifResult{inner: tile_mode_type.ast},
      meta: %{inner: tile_mode_type}
    }

    into_option_tile_mode_type = %Type{
      kind: :impl_trait,
      rust: "impl Into<Option<TileMode>>",
      ast: %AST.TypeRaw{source: "impl Into<Option<TileMode>>"},
      meta: %{
        traits: [
          %Type{
            kind: :type,
            rust: "Into<Option<TileMode>>",
            ast: %AST.TypePath{parts: [:Into]},
            meta: %{syn_name: "Into", args: [option_tile_mode_type]}
          }
        ]
      }
    }

    term_type = %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}}

    statements =
      Lower.quoted_body(
        quote do
          blur(decode_tile_mode(term))
          :ok
        end,
        unit_type(),
        %{term: term_type},
        callables: [
          %Callable{
            name: "decode_tile_mode",
            kind: :function,
            args: [%{name: "term", type: term_type, syn: nil}],
            returns: nif_tile_mode_type
          },
          %Callable{
            name: "blur",
            kind: :function,
            args: [%{name: "tile_mode", type: into_option_tile_mode_type, syn: nil}],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.LocalCall{
                 name: :blur,
                 args: [%AST.Try{expr: %AST.LocalCall{name: :decode_tile_mode}}]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers propagation through impl Into option arguments" do
    image_filter_type = %Type{
      kind: :type,
      rust: "ImageFilter",
      ast: %AST.TypePath{parts: [:ImageFilter]}
    }

    option_filter_type = %Type{
      kind: :option,
      rust: "Option<ImageFilter>",
      ast: %AST.TypeOption{inner: image_filter_type.ast},
      meta: %{inner: image_filter_type}
    }

    nif_option_filter_type = %Type{
      kind: :nif_result,
      rust: "NifResult<Option<ImageFilter>>",
      ast: %AST.TypeNifResult{inner: option_filter_type.ast},
      meta: %{inner: option_filter_type}
    }

    into_option_filter_type = %Type{
      kind: :impl_trait,
      rust: "impl Into<Option<ImageFilter>>",
      ast: %AST.TypeRaw{source: "impl Into<Option<ImageFilter>>"},
      meta: %{
        traits: [
          %Type{
            kind: :type,
            rust: "Into<Option<ImageFilter>>",
            ast: %AST.TypePath{parts: [:Into]},
            meta: %{syn_name: "Into", args: [option_filter_type]}
          }
        ]
      }
    }

    term_type = %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}}

    statements =
      Lower.quoted_body(
        quote do
          offset(optional_image_filter_from_term(term))
          ImageFilters.offset(term, optional_image_filter_from_term(term), term)
          :ok
        end,
        unit_type(),
        %{term: term_type},
        callables: [
          %Callable{
            name: "optional_image_filter_from_term",
            kind: :function,
            args: [%{name: "term", type: term_type, syn: nil}],
            returns: nif_option_filter_type
          },
          %Callable{
            name: "offset",
            kind: :function,
            args: [%{name: "input", type: into_option_filter_type, syn: nil}],
            returns: unit_type()
          },
          %Callable{
            name: "offset",
            kind: :function,
            args: [
              %{name: "offset", type: term_type, syn: nil},
              %{name: "input", type: into_option_filter_type, syn: nil},
              %{name: "crop_rect", type: term_type, syn: nil}
            ],
            returns: unit_type()
          },
          %Callable{
            name: "offset",
            kind: :method,
            target: "ImageFilter",
            args: [
              %{name: "self", type: image_filter_type, syn: nil},
              %{name: "crop_rect", type: term_type, syn: nil},
              %{name: "delta", type: term_type, syn: nil}
            ],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.LocalCall{
                 name: :offset,
                 args: [%AST.Try{expr: %AST.LocalCall{name: :optional_image_filter_from_term}}]
               }
             },
             %AST.ExprStmt{
               expr: %AST.PathCall{
                 path: %AST.Path{parts: [:image_filters, :offset]},
                 args: [
                   %AST.Var{name: :term},
                   %AST.Try{expr: %AST.LocalCall{name: :optional_image_filter_from_term}},
                   %AST.Var{name: :term}
                 ]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers propagation inside some wrapper arguments" do
    clip_type = %Type{kind: :type, rust: "ClipOp", ast: %AST.TypePath{parts: [:ClipOp]}}

    option_clip = %Type{
      kind: :option,
      rust: "Option<ClipOp>",
      ast: %AST.TypeOption{inner: clip_type.ast},
      meta: %{inner: clip_type}
    }

    nif_clip = %Type{
      kind: :nif_result,
      rust: "NifResult<ClipOp>",
      ast: %AST.TypeNifResult{inner: clip_type.ast},
      meta: %{inner: clip_type}
    }

    nif_option_clip = %Type{
      kind: :nif_result,
      rust: "NifResult<Option<ClipOp>>",
      ast: %AST.TypeNifResult{inner: option_clip.ast},
      meta: %{inner: option_clip}
    }

    atom_type = %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}}

    statements =
      Lower.quoted_body(
        quote(do: {:ok, some(decode_clip(value))}),
        nif_option_clip,
        %{value: atom_type},
        callables: [
          %Callable{
            name: "decode_clip",
            kind: :function,
            args: [%{name: "value", type: atom_type, syn: nil}],
            returns: nif_clip
          }
        ]
      )

    assert [
             %AST.Return{
               expr: %AST.Ok{
                 expr: %AST.Some{expr: %AST.Try{expr: %AST.LocalCall{name: :decode_clip}}}
               }
             }
           ] = statements
  end

  test "infers statement-position propagation for matching wrapper returns" do
    unit = unit_type()

    nif_unit = %Type{
      kind: :nif_result,
      rust: "NifResult<()>",
      ast: %AST.TypeNifResult{inner: unit.ast},
      meta: %{inner: unit}
    }

    statements =
      Lower.quoted_body(
        quote do
          maybe_unit()
          :ok
        end,
        nif_unit,
        %{},
        callables: [
          %Callable{name: "maybe_unit", kind: :function, args: [], returns: nif_unit}
        ]
      )

    assert [
             %AST.ExprStmt{expr: %AST.Try{expr: %AST.LocalCall{name: :maybe_unit}}},
             %AST.Return{expr: %AST.Ok{}}
           ] = statements
  end
end
