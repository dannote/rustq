Code.require_file("../../support/rustq_meta_generated_case.ex", __DIR__)

defmodule RustQ.Meta.AttrCase do
  use RustQ.Meta

  alias RustQ.Type, as: R

  @allow :dead_code
  @nif schedule: "DirtyCpu"
  @spec render(term()) :: R.nif_result(term())
  defrust render(term) do
    render_impl(term)
  end
end

defmodule RustQ.Meta.LowerTest do
  use ExUnit.Case, async: true

  alias RustQ.Binding.Callable
  alias RustQ.Codegen.Decoders
  alias RustQ.Codegen.Helpers
  alias RustQ.Diagnostic
  alias RustQ.Meta.AttrCase
  alias RustQ.Meta.GeneratedCase, as: Generated
  alias RustQ.Meta.Lower
  alias RustQ.Meta.Type
  alias RustQ.Rust.AST
  alias RustQ.Rust.AST.{Attribute, ExprStmt, Function, FunctionArg, MethodCall}

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
    tile_mode_type = %Type{kind: :type, rust: "TileMode", ast: %AST.TypePath{parts: [:TileMode]}}

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

  test "infers let RHS propagation when pattern type is known" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          value = maybe_path()
          :ok
        end,
        unit_type(),
        %{value: path_type},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert [
             %AST.Let{
               pattern: %AST.PatVar{name: :value},
               expr: %AST.Try{expr: %AST.LocalCall{name: :maybe_path}}
             },
             %AST.Return{}
           ] = statements
  end

  test "infers let propagation from downstream callable argument type" do
    tile_mode = %Type{kind: :type, rust: "TileMode", ast: %AST.TypePath{parts: [:TileMode]}}

    nif_tile_mode = %Type{
      kind: :nif_result,
      rust: "NifResult<TileMode>",
      ast: %AST.TypeNifResult{inner: tile_mode.ast},
      meta: %{inner: tile_mode}
    }

    atom_type = %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}}

    statements =
      Lower.quoted_body(
        quote do
          mode = decode_mode(atom)
          consume_mode(mode)
          :ok
        end,
        unit_type(),
        %{atom: atom_type},
        callables: [
          %Callable{
            name: "decode_mode",
            kind: :function,
            args: [%{name: "atom", type: atom_type, syn: nil}],
            returns: nif_tile_mode
          },
          %Callable{
            name: "consume_mode",
            kind: :function,
            args: [%{name: "mode", type: tile_mode, syn: nil}],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.Let{
               pattern: %AST.PatVar{name: :mode},
               expr: %AST.Try{expr: %AST.LocalCall{name: :decode_mode}}
             },
             %AST.ExprStmt{expr: %AST.LocalCall{name: :consume_mode}},
             %AST.Return{}
           ] = statements
  end

  test "infers let propagation from downstream path call argument inside statement clauses" do
    tile_mode = %Type{kind: :type, rust: "TileMode", ast: %AST.TypePath{parts: [:TileMode]}}

    nif_tile_mode = %Type{
      kind: :nif_result,
      rust: "NifResult<TileMode>",
      ast: %AST.TypeNifResult{inner: tile_mode.ast},
      meta: %{inner: tile_mode}
    }

    atom_type = %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}}
    matrix_type = %Type{kind: :type, rust: "Matrix", ast: %AST.TypePath{parts: [:Matrix]}}

    option_matrix_type = %Type{
      kind: :option,
      rust: "Option<Matrix>",
      ast: %AST.TypeOption{inner: matrix_type.ast},
      meta: %{inner: matrix_type}
    }

    nif_option_matrix_type = %Type{
      kind: :nif_result,
      rust: "NifResult<Option<Matrix>>",
      ast: %AST.TypeNifResult{inner: option_matrix_type.ast},
      meta: %{inner: option_matrix_type}
    }

    effect_type = %Type{
      kind: :type,
      rust: "RuntimeEffect",
      ast: %AST.TypePath{parts: [:RuntimeEffect]}
    }

    image_type = %Type{kind: :type, rust: "Image", ast: %AST.TypePath{parts: [:Image]}}

    nif_effect_type = %Type{
      kind: :nif_result,
      rust: "NifResult<RuntimeEffect>",
      ast: %AST.TypeNifResult{inner: effect_type.ast},
      meta: %{inner: effect_type}
    }

    nif_image_type = %Type{
      kind: :nif_result,
      rust: "NifResult<Image>",
      ast: %AST.TypeNifResult{inner: image_type.ast},
      meta: %{inner: image_type}
    }

    tile_pair_type = %Type{
      kind: :tuple,
      rust: "(TileMode, TileMode)",
      ast: %AST.TypeRaw{source: "(TileMode, TileMode)"},
      meta: %{elements: [tile_mode, tile_mode]}
    }

    option_tile_pair_type = %Type{
      kind: :option,
      rust: "Option<(TileMode, TileMode)>",
      ast: %AST.TypeOption{inner: tile_pair_type.ast},
      meta: %{inner: tile_pair_type}
    }

    into_option_tile_pair_type = %Type{
      kind: :impl_trait,
      rust: "impl Into<Option<(TileMode, TileMode)>>",
      ast: %AST.TypeRaw{source: "impl Into<Option<(TileMode, TileMode)>>"},
      meta: %{
        traits: [
          %Type{
            kind: :type,
            rust: "Into<Option<(TileMode, TileMode)>>",
            ast: %AST.TypePath{parts: [:Into]},
            meta: %{syn_name: "Into", args: [option_tile_pair_type]}
          }
        ]
      }
    }

    into_atom_type = %Type{
      kind: :impl_trait,
      rust: "impl Into<Atom>",
      ast: %AST.TypeRaw{source: "impl Into<Atom>"},
      meta: %{
        traits: [
          %Type{
            kind: :type,
            rust: "Into<Atom>",
            ast: %AST.TypePath{parts: [:Into]},
            meta: %{syn_name: "Into", args: [atom_type]}
          }
        ]
      }
    }

    into_option_matrix_ref_type = %Type{
      kind: :impl_trait,
      rust: "impl Into<Option<&Matrix>>",
      ast: %AST.TypeRaw{source: "impl Into<Option<&Matrix>>"},
      meta: %{
        traits: [
          %Type{
            kind: :type,
            rust: "Into<Option<&Matrix>>",
            ast: %AST.TypePath{parts: [:Into]},
            meta: %{
              syn_name: "Into",
              args: [
                %Type{
                  kind: :option,
                  rust: "Option<&Matrix>",
                  ast: %AST.TypeOption{inner: %AST.TypeRef{inner: matrix_type.ast}},
                  meta: %{
                    inner: %Type{
                      kind: :ref,
                      rust: "&Matrix",
                      ast: %AST.TypeRef{inner: matrix_type.ast},
                      meta: %{inner: matrix_type}
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }

    statements =
      Lower.quoted_body(
        quote do
          if tag == atom do
            effect = unwrap!(runtime_effect_from_term(atom))
            image = unwrap!(image_from_term(atom))
            mode = GeneratedEnums.decode_mode(atom)
            mode_2 = GeneratedEnums.decode_mode(atom)
            matrix = optional_matrix_from_term(atom)

            effect.make_shader(atom, atom, matrix.as_ref())
            image.to_shader({mode, mode_2}, atom, matrix.as_ref())

            Shader.linear_gradient(
              atom,
              atom,
              atom,
              mode,
              none(),
              matrix.as_ref()
            )
          end

          :ok
        end,
        unit_type(),
        %{atom: atom_type, tag: atom_type, mode: atom_type},
        callables: [
          %Callable{
            name: "decode_mode",
            kind: :function,
            target: "GeneratedEnums",
            args: [%{name: "atom", type: atom_type, syn: nil}],
            returns: nif_tile_mode
          },
          %Callable{
            name: "runtime_effect_from_term",
            kind: :function,
            args: [%{name: "term", type: atom_type, syn: nil}],
            returns: nif_effect_type
          },
          %Callable{
            name: "image_from_term",
            kind: :function,
            args: [%{name: "term", type: atom_type, syn: nil}],
            returns: nif_image_type
          },
          %Callable{
            name: "optional_matrix_from_term",
            kind: :function,
            args: [%{name: "term", type: atom_type, syn: nil}],
            returns: nif_option_matrix_type
          },
          %Callable{
            name: "make_shader",
            kind: :method,
            target: "RuntimeEffect",
            args: [
              %{name: "uniforms", type: atom_type, syn: nil},
              %{name: "children", type: atom_type, syn: nil},
              %{name: "matrix", type: into_option_matrix_ref_type, syn: nil}
            ],
            returns: unit_type()
          },
          %Callable{
            name: "to_shader",
            kind: :method,
            target: "Image",
            args: [
              %{name: "tile_modes", type: into_option_tile_pair_type, syn: nil},
              %{name: "sampling", type: into_atom_type, syn: nil},
              %{name: "matrix", type: into_option_matrix_ref_type, syn: nil}
            ],
            returns: unit_type()
          },
          %Callable{
            name: "linear_gradient",
            kind: :method,
            target: "Shader",
            args: [
              %{name: "points", type: atom_type, syn: nil},
              %{name: "colors", type: atom_type, syn: nil},
              %{name: "positions", type: atom_type, syn: nil},
              %{name: "mode", type: tile_mode, syn: nil},
              %{name: "flags", type: atom_type, syn: nil},
              %{name: "matrix", type: into_option_matrix_ref_type, syn: nil}
            ],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.If{
                 then: [
                   %AST.Let{
                     pattern: %AST.PatVar{name: :effect},
                     expr: %AST.Try{expr: %AST.LocalCall{name: :runtime_effect_from_term}}
                   },
                   %AST.Let{
                     pattern: %AST.PatVar{name: :image},
                     expr: %AST.Try{expr: %AST.LocalCall{name: :image_from_term}}
                   },
                   %AST.Let{
                     pattern: %AST.PatVar{name: :mode},
                     expr: %AST.Try{
                       expr: %AST.PathCall{
                         path: %AST.Path{parts: [:generated_enums, :decode_mode]}
                       }
                     }
                   },
                   %AST.Let{
                     pattern: %AST.PatVar{name: :mode_2},
                     expr: %AST.Try{
                       expr: %AST.PathCall{
                         path: %AST.Path{parts: [:generated_enums, :decode_mode]}
                       }
                     }
                   },
                   %AST.Let{
                     pattern: %AST.PatVar{name: :matrix},
                     expr: %AST.Try{expr: %AST.LocalCall{name: :optional_matrix_from_term}}
                   },
                   %AST.ExprStmt{expr: %AST.MethodCall{method: :make_shader}},
                   %AST.ExprStmt{expr: %AST.MethodCall{method: :to_shader}},
                   %AST.ExprStmt{
                     expr: %AST.PathCall{path: %AST.Path{parts: [:Shader, :linear_gradient]}}
                   }
                 ]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers tuple-pattern let propagation from callable return metadata" do
    color_vec = %Type{kind: :type, rust: "Vec<Color>", ast: %AST.TypePath{parts: [:Vec]}}

    positions = %Type{
      kind: :option,
      rust: "Option<Vec<f32>>",
      ast: %AST.TypeOption{inner: %AST.TypePath{parts: [:Vec]}}
    }

    tuple = %Type{
      kind: :tuple,
      rust: "(Vec<Color>, Option<Vec<f32>>)",
      ast: %AST.TypeRaw{source: "(Vec<Color>, Option<Vec<f32>>)"},
      meta: %{elements: [color_vec, positions]}
    }

    nif_tuple = %Type{
      kind: :nif_result,
      rust: "NifResult<(Vec<Color>, Option<Vec<f32>>)",
      ast: %AST.TypeNifResult{inner: tuple.ast},
      meta: %{inner: tuple}
    }

    stops_type = %Type{kind: :type, rust: "Vec<Term>", ast: %AST.TypePath{parts: [:Vec]}}

    statements =
      Lower.quoted_body(
        quote do
          {colors, positions} = decode_stops(stops)
          :ok
        end,
        unit_type(),
        %{stops: stops_type},
        callables: [
          %Callable{
            name: "decode_stops",
            kind: :function,
            args: [%{name: "stops", type: stops_type, syn: nil}],
            returns: nif_tuple
          }
        ]
      )

    assert [
             %AST.Let{
               pattern: %AST.PatTuple{},
               expr: %AST.Try{expr: %AST.LocalCall{name: :decode_stops}}
             },
             %AST.Return{}
           ] = statements
  end

  test "infers let propagation from downstream receiver method type" do
    image_type = %Type{kind: :type, rust: "Image", ast: %AST.TypePath{parts: [:Image]}}
    shader_type = %Type{kind: :type, rust: "Shader", ast: %AST.TypePath{parts: [:Shader]}}
    term_type = %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}}

    statements =
      Lower.quoted_body(
        quote do
          image = image_from_term(term)
          image.to_shader()
          :ok
        end,
        %Type{
          kind: :nif_result,
          rust: "NifResult<()>",
          ast: %AST.TypeNifResult{inner: %AST.TypeUnit{}}
        },
        %{term: term_type},
        callables: [
          %Callable{
            name: "image_from_term",
            kind: :function,
            args: [%{name: "term", type: term_type, syn: nil}],
            returns: %Type{
              kind: :nif_result,
              rust: "NifResult<Image>",
              ast: %AST.TypeNifResult{inner: image_type.ast},
              meta: %{inner: image_type}
            }
          },
          %Callable{
            name: "to_shader",
            kind: :method,
            target: "Image",
            args: [%{name: "self", type: image_type, syn: nil}],
            returns: %Type{
              kind: :option,
              rust: "Option<Shader>",
              ast: %AST.TypeOption{inner: shader_type.ast},
              meta: %{inner: shader_type}
            }
          }
        ]
      )

    assert [
             %AST.Let{
               pattern: %AST.PatVar{name: :image},
               expr: %AST.Try{expr: %AST.LocalCall{name: :image_from_term}}
             },
             %AST.ExprStmt{expr: %AST.MethodCall{method: :to_shader}},
             %AST.Return{expr: %AST.Ok{}}
           ] = statements
  end

  test "infers vector push argument propagation from downstream return type" do
    color_type = %Type{kind: :type, rust: "Color", ast: %AST.TypePath{parts: [:Color]}}

    vec_color_type = %Type{
      kind: :vec,
      rust: "Vec<Color>",
      ast: %AST.TypeVec{inner: color_type.ast},
      meta: %{inner: color_type}
    }

    return_type = %Type{
      kind: :nif_result,
      rust: "NifResult<Vec<Color>>",
      ast: %AST.TypeNifResult{inner: vec_color_type.ast},
      meta: %{inner: vec_color_type}
    }

    term_type = %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}}

    statements =
      Lower.quoted_body(
        quote do
          colors = Vec.with_capacity(stops.len())

          for stop <- stops do
            colors.push(decode_color(stop))
          end

          {:ok, colors}
        end,
        return_type,
        %{
          stops: %Type{
            kind: :vec,
            rust: "Vec<Term>",
            ast: %AST.TypeVec{inner: term_type.ast},
            meta: %{inner: term_type}
          }
        },
        callables: [
          %Callable{
            name: "decode_color",
            kind: :function,
            args: [%{name: "term", type: term_type, syn: nil}],
            returns: %Type{
              kind: :nif_result,
              rust: "NifResult<Color>",
              ast: %AST.TypeNifResult{inner: color_type.ast},
              meta: %{inner: color_type}
            }
          }
        ]
      )

    assert [
             %AST.Let{},
             %AST.For{
               body: [
                 %AST.ExprStmt{
                   expr: %AST.MethodCall{
                     method: :push,
                     args: [%AST.Try{expr: %AST.LocalCall{name: :decode_color}}]
                   }
                 }
               ]
             },
             %AST.Return{expr: %AST.Ok{expr: %AST.Var{name: :colors}}}
           ] = statements
  end

  test "infers assignment RHS propagation when target type is known" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          assign!(value, maybe_path())
          :ok
        end,
        unit_type(),
        %{value: path_type},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert [
             %AST.Assign{
               target: %AST.Var{name: :value},
               expr: %AST.Try{expr: %AST.LocalCall{name: :maybe_path}}
             },
             %AST.Return{}
           ] = statements
  end

  test "does not infer propagation for let RHS when pattern type is unknown" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          value = maybe_path()
          :ok
        end,
        unit_type(),
        %{},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert [
             %AST.Let{
               pattern: %AST.PatVar{name: :value},
               expr: %AST.LocalCall{name: :maybe_path}
             },
             %AST.Return{}
           ] = statements
  end

  test "infers local call argument propagation from callable arg types" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          draw_path(maybe_path())
          :ok
        end,
        unit_type(),
        %{},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path},
          %Callable{
            name: "draw_path",
            kind: :function,
            args: [%{name: "path", type: path_type, syn: nil}],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.LocalCall{
                 name: :draw_path,
                 args: [%AST.Try{expr: %AST.LocalCall{name: :maybe_path}}]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers remote call argument propagation from free-function callable metadata" do
    mode_type = %Type{kind: :type, rust: "Mode", ast: %AST.TypePath{parts: [:Mode]}}

    result_mode = %Type{
      kind: :nif_result,
      rust: "NifResult<Mode>",
      ast: %AST.TypeNifResult{inner: mode_type.ast},
      meta: %{inner: mode_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          paint.set_blend_mode(GeneratedEnums.decode_blend_mode(atom))
          :ok
        end,
        unit_type(),
        %{
          paint: %Type{
            kind: :mut_ref,
            rust: "&mut skia_safe::Paint",
            ast: %AST.TypeRef{inner: %AST.TypePath{parts: [:skia_safe, :Paint]}, mutable: true}
          },
          atom: %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}}
        },
        callables: [
          %Callable{
            name: "decode_blend_mode",
            kind: :function,
            args: [
              %{
                name: "atom",
                type: %Type{kind: :atom, rust: "Atom", ast: %AST.TypePath{parts: [:Atom]}},
                syn: nil
              }
            ],
            returns: result_mode
          },
          %Callable{
            name: "set_blend_mode",
            kind: :method,
            target: "Paint",
            args: [self_arg(), %{name: "mode", type: mode_type, syn: nil}],
            returns: nil
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.MethodCall{
                 method: :set_blend_mode,
                 args: [
                   %AST.Try{
                     expr: %AST.PathCall{
                       path: %AST.Path{parts: [:generated_enums, :decode_blend_mode]}
                     }
                   }
                 ]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers remote call argument propagation from callable arg types" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    result_path = %Type{
      kind: :result,
      rust: "Result<Path, Error>",
      ast: %AST.TypeResult{ok: path_type.ast, error: %AST.TypePath{parts: [:Error]}},
      meta: %{ok: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          Generated.draw_path(Generated.decode_path(term))
          :ok
        end,
        unit_type(),
        %{term: %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}}},
        callables: [
          %Callable{
            name: "decode_path",
            kind: :function,
            target: "Generated",
            args: [
              %{
                name: "term",
                type: %Type{kind: :term, rust: "Term", ast: %AST.TypePath{parts: [:Term]}},
                syn: nil
              }
            ],
            returns: result_path
          },
          %Callable{
            name: "draw_path",
            kind: :function,
            target: "Generated",
            args: [%{name: "path", type: path_type, syn: nil}],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.PathCall{
                 path: %AST.Path{parts: [:Generated, :draw_path]},
                 args: [
                   %AST.Try{
                     expr: %AST.PathCall{path: %AST.Path{parts: [:Generated, :decode_path]}}
                   }
                 ]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "infers method call argument propagation from typed receiver metadata" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}
    canvas_type = %Type{kind: :type, rust: "Canvas", ast: %AST.TypePath{parts: [:Canvas]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          canvas.draw_path(maybe_path())
          :ok
        end,
        unit_type(),
        %{canvas: canvas_type},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path},
          %Callable{
            name: "draw_path",
            kind: :method,
            target: "Canvas",
            args: [self_arg(), %{name: "path", type: path_type, syn: nil}],
            returns: unit_type()
          }
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.MethodCall{
                 receiver: %AST.Var{name: :canvas},
                 method: :draw_path,
                 args: [%AST.Try{expr: %AST.LocalCall{name: :maybe_path}}]
               }
             },
             %AST.Return{}
           ] = statements
  end

  test "does not infer argument propagation without callee metadata" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(
        quote do
          draw_path(maybe_path())
          :ok
        end,
        unit_type(),
        %{},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert [
             %AST.ExprStmt{
               expr: %AST.LocalCall{name: :draw_path, args: [%AST.LocalCall{name: :maybe_path}]}
             },
             %AST.Return{}
           ] = statements
  end

  test "does not infer propagation when expected type is still the wrapper" do
    path_type = %Type{kind: :type, rust: "Path", ast: %AST.TypePath{parts: [:Path]}}

    option_path = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeOption{inner: path_type.ast},
      meta: %{inner: path_type}
    }

    statements =
      Lower.quoted_body(quote(do: maybe_path()), option_path, %{},
        callables: [
          %Callable{name: "maybe_path", kind: :function, args: [], returns: option_path}
        ]
      )

    assert [
             %AST.Return{
               expr: %AST.Some{expr: %AST.LocalCall{name: :maybe_path, args: []}}
             }
           ] =
             statements
  end

  test "looks up callable return types from metadata" do
    return_type = %Type{
      kind: :option,
      rust: "Option<Path>",
      ast: %AST.TypeRaw{source: "Option<Path>"}
    }

    callables = [
      %Callable{name: "maybe_path", kind: :function, args: [], returns: return_type},
      %Callable{
        name: "draw_rect",
        kind: :method,
        target: "Canvas",
        args: [self_arg(), rect_arg()],
        returns: return_type
      }
    ]

    assert Lower.callable_return_type(quote(do: maybe_path()), callables: callables) ==
             return_type

    assert Lower.callable_return_type(quote(do: Canvas.draw_rect(rect)), callables: callables) ==
             return_type

    assert Lower.callable_return_type(quote(do: missing()), callables: callables) == nil
  end

  test "defrust consumes idiomatic Rust-facing attributes" do
    assert %Function{attrs: attrs} =
             AttrCase.__rustq_asts__()
             |> Enum.find(&(&1.name == :render))

    assert [
             %Attribute{path: [:rustler, :nif], args: [schedule: "DirtyCpu"]},
             %Attribute{path: [:allow], args: [:dead_code]}
           ] = attrs

    source = AttrCase.__rustq_source__()
    assert source =~ ~s|#[rustler::nif(schedule = "DirtyCpu")]|
    assert source =~ "#[allow(dead_code)]"
  end

  test "generated ASTs are retained before fragment validation" do
    [draw_save, decode_mode, draw_rect, maybe_save | _] = Generated.__rustq_asts__()

    assert %Function{
             name: :draw_save,
             args: [%FunctionArg{name: :canvas, type: %RustQ.Rust.AST.TypeRef{}}]
           } = draw_save

    assert %RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}} = hd(decode_mode.body)

    assert %Function{
             args: [
               _canvas_arg,
               %FunctionArg{name: :opts, type: %RustQ.Rust.AST.TypePath{}},
               _raw_opts_arg
             ]
           } = draw_rect

    assert %RustQ.Rust.AST.Let{pattern: %RustQ.Rust.AST.PatVar{name: :rect}} = hd(draw_rect.body)

    assert Enum.any?(
             draw_rect.body,
             &match?(
               %RustQ.Rust.AST.Let{pattern: %RustQ.Rust.AST.PatVar{name: :paint}, mutable: true},
               &1
             )
           )

    assert %RustQ.Rust.AST.ExprStmt{
             expr: %RustQ.Rust.AST.Match{
               arms: [
                 %RustQ.Rust.AST.Arm{pattern: %RustQ.Rust.AST.PatNone{}},
                 %RustQ.Rust.AST.Arm{pattern: %RustQ.Rust.AST.PatSome{}}
               ]
             }
           } = hd(maybe_save.body)
  end

  test "unsupported lowerer patterns raise structured diagnostics" do
    binding_diagnostic =
      try do
        Lower.quoted_body(
          quote do
            %{value: value} = term
            :ok
          end,
          nil
        )

        flunk("expected diagnostic")
      rescue
        error in Diagnostic.Error -> error.diagnostic
      end

    assert binding_diagnostic.phase == :lower
    assert binding_diagnostic.kind == :unsupported_binding_pattern
    assert binding_diagnostic.snippet == "%{value: value}"
    assert binding_diagnostic.message =~ "unsupported defrust binding pattern"
    assert binding_diagnostic.suggestion =~ "variable or tuple pattern"

    match_diagnostic =
      try do
        Lower.quoted_body(
          quote do
            case term do
              %{value: value} -> value
            end
          end,
          nil
        )

        flunk("expected diagnostic")
      rescue
        error in Diagnostic.Error -> error.diagnostic
      end

    assert match_diagnostic.phase == :lower
    assert match_diagnostic.kind == :unsupported_match_pattern
    assert match_diagnostic.snippet == "%{value: value}"
    assert match_diagnostic.message =~ "unsupported defrust match pattern"
  end

  test "non-raw semantic helpers lower directly to AST nodes" do
    assert [
             %AST.Return{
               expr: %AST.Some{expr: %AST.Var{name: :value}}
             }
           ] = Lower.quoted_body(quote(do: expr!(some(value))), nil)

    assert [
             %AST.Return{
               expr: %AST.PatOk{pattern: %AST.PatVar{name: :value}}
             }
           ] = Lower.quoted_body(quote(do: pat!({:ok, value})), nil)

    assert [
             %AST.Return{
               expr: %AST.ExprStmt{expr: %AST.MethodCall{method: :clear}}
             }
           ] = Lower.quoted_body(quote(do: stmt!(canvas.clear(color))), nil)

    assert [
             %AST.Return{
               expr: %AST.Arm{
                 pattern: %AST.PatOk{pattern: %AST.PatVar{name: :value}},
                 body: [%AST.Return{expr: %AST.Var{name: :value}}]
               }
             }
           ] = Lower.quoted_body(quote(do: arm!({:ok, value}, value)), nil)
  end

  test "defrust lowers closures and deref in method chains" do
    defmodule ClosureDerefCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec maybe_decode_color(R.ref(Canvas.t()), R.vec(term())) :: R.nif_result(R.unit())
      defrust maybe_decode_color(canvas, args) do
        case args.first().and_then(fn term -> decode_color(deref(term)).ok() end) do
          {:some, color} -> canvas.clear(color)
          :none -> :ok
        end

        :ok
      end
    end

    source = ClosureDerefCase.__rustq_source__()

    assert source =~ "args.first().and_then(|term| decode_color(*term).ok())"
    assert source =~ "Some(color) =>"
    assert source =~ "canvas.clear(color);"
  end

  test "defrust option cases use Elixir tuple and atom patterns" do
    defmodule OptionCase do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec save_if_present(R.ref(Canvas.t()), R.option(R.f32())) :: R.nif_result(R.unit())
      defrust save_if_present(canvas, maybe_alpha) do
        case maybe_alpha do
          {:some, alpha} -> canvas.save_layer_alpha(alpha)
          :none -> :ok
        end

        :ok
      end
    end

    assert %AST.Function{
             body: [
               %AST.ExprStmt{
                 expr: %AST.Match{
                   arms: [
                     %AST.Arm{pattern: %AST.PatSome{pattern: %AST.PatVar{name: :alpha}}},
                     %AST.Arm{pattern: %AST.PatNone{}}
                   ]
                 }
               },
               %AST.Return{expr: %AST.Ok{}}
             ]
           } = OptionCase.__rustq_asts__() |> List.first()

    source = OptionCase.__rustq_source__()
    assert source =~ "Some(alpha) =>"
    assert source =~ "None =>"
  end

  test "dogfooded native helpers lower binary operators and Rust string types" do
    helpers = Helpers.__rustq_asts__()

    assert %Function{
             name: :required_field,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.MethodCall{method: :map_get}}]
           } = Enum.find(helpers, &(&1.name == :required_field))

    assert %Function{
             name: :optional_map_get,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Match{}}]
           } = Enum.find(helpers, &(&1.name == :optional_map_get))

    assert %Function{
             name: :atom_key,
             args: [
               %FunctionArg{
                 name: :term,
                 type: %RustQ.Rust.AST.TypePath{parts: [:Term], lifetimes: [:a]}
               },
               %FunctionArg{
                 name: :key,
                 type: %RustQ.Rust.AST.TypeRef{inner: %RustQ.Rust.AST.TypePath{parts: [:str]}}
               }
             ],
             returns: %RustQ.Rust.AST.TypeNifResult{
               inner: %RustQ.Rust.AST.TypePath{parts: [:String]}
             }
           } = Enum.find(helpers, &(&1.name == :atom_key))

    assert %Function{name: :optional_atom_key, body: optional_body} =
             Enum.find(helpers, &(&1.name == :optional_atom_key))

    assert Enum.any?(
             optional_body,
             &match?(%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{}}, &1)
           )

    assert %Function{name: :is_nil, body: body} =
             Enum.find(helpers, &(&1.name == :is_nil))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Ok{expr: %RustQ.Rust.AST.BinaryOp{op: :and}}
             }
           ] =
             body

    assert %Function{
             name: :expect_struct,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{else: else_body}}]
           } =
             Enum.find(helpers, &(&1.name == :expect_struct))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Err{
                 expr: %RustQ.Rust.AST.Path{parts: [:rustler, :Error, :BadArg]}
               }
             }
           ] = else_body
  end

  test "ordinary syntax lowers to RustQ AST while native decoders use structural helpers" do
    draw_rect = Enum.find(Generated.__rustq_asts__(), &(&1.name == :draw_rect))

    decode_expr_ref =
      Enum.find(Decoders.asts(), &(&1.name == :decode_expr_ref))

    assert Enum.any?(
             draw_rect.body,
             &match?(%ExprStmt{expr: %MethodCall{}}, &1)
           )

    assert inspect(draw_rect) =~ "RustQ.Rust.AST.Ref"

    assert %Function{
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{path: %RustQ.Rust.AST.Path{parts: ref_parts}}
               }
             ]
           } = decode_expr_ref

    assert ref_parts == [:super, :parse_ref_expr]
  end

  test "nested branches use expected return type wrapping" do
    asts = Generated.__rustq_asts__()

    assert %Function{
             name: :nested_option,
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.Match{arms: [nil_arm, value_arm]}
               }
             ]
           } = Enum.find(asts, &(&1.name == :nested_option))

    assert %RustQ.Rust.AST.Arm{body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.None{}}]} =
             nil_arm

    assert %RustQ.Rust.AST.Arm{
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.If{then: then_body, else: else_body}
               }
             ]
           } = value_arm

    assert [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.None{}}] = then_body

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Some{expr: %RustQ.Rust.AST.Var{name: :value}}
             }
           ] =
             else_body

    assert %Function{
             name: :nested_result,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{then: result_then}}]
           } = Enum.find(asts, &(&1.name == :nested_result))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Match{
                 arms: [
                   %RustQ.Rust.AST.Arm{
                     body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Ok{}}]
                   },
                   %RustQ.Rust.AST.Arm{
                     body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.Err{}}]
                   }
                 ]
               }
             }
           ] = result_then

    assert %Function{
             name: :nested_nif_result,
             body: [%RustQ.Rust.AST.Return{expr: %RustQ.Rust.AST.If{else: nif_else}}]
           } = Enum.find(asts, &(&1.name == :nested_nif_result))

    assert [
             %RustQ.Rust.AST.Return{
               expr: %RustQ.Rust.AST.Err{expr: %RustQ.Rust.AST.NifRaiseAtom{name: :not_ready}}
             }
           ] = nif_else
  end

  test "dogfooded decoder wrappers lower Super calls and Rust constructors" do
    decoders = Decoders.asts()

    assert %Function{
             name: :decode_expr_try,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, :parse_try_expr]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_try))

    assert %Function{
             name: :decode_pat_some,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, :parse_some_pat]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_pat_some))

    assert %Function{
             name: :decode_stmt_return,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.Ok{
                   expr: %RustQ.Rust.AST.PathCall{
                     path: %RustQ.Rust.AST.Path{parts: [:Stmt, :Expr]}
                   }
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_stmt_return))

    assert %Function{
             name: :decode_expr_ok,
             body: [
               %RustQ.Rust.AST.Let{},
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, :parse_ok_expr]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_ok))

    assert %Function{
             name: :decode_expr_none,
             body: [
               %RustQ.Rust.AST.Return{
                 expr: %RustQ.Rust.AST.PathCall{
                   path: %RustQ.Rust.AST.Path{parts: [:super, :parse_none_expr]}
                 }
               }
             ]
           } = Enum.find(decoders, &(&1.name == :decode_expr_none))
  end

  defp unit_type, do: %Type{kind: :unit, rust: "()", ast: %AST.TypeUnit{}}

  defp self_arg,
    do: %{
      name: "self",
      type: %Type{kind: :ref, rust: "&Self", ast: %AST.TypeRaw{source: "&Self"}},
      syn: nil
    }

  defp rect_arg,
    do: %{
      name: "rect",
      type: %Type{kind: :type, rust: "Rect", ast: %AST.TypeRaw{source: "Rect"}},
      syn: nil
    }
end
