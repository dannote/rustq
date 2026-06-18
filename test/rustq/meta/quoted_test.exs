defmodule RustQ.Meta.QuotedTest do
  use ExUnit.Case, async: true

  alias RustQ.Rust.AST.Builder, as: A

  test "quoted accepts explicit Rust AST types" do
    function =
      RustQ.Meta.quoted(:draw_translate_impl,
        args: [
          canvas: A.ref_type([:skia_safe, :Canvas]),
          opts: A.type_path([:generated_opts, :TranslateOpts], lifetimes: [:a]),
          _raw_opts: "&[(Atom, Term<'a>)]"
        ],
        returns: A.nif_result_type(A.unit_type()),
        do:
          quote do
            canvas.translate({opts.x, opts.y})
            :ok
          end
      )

    source = RustQ.Rust.AST.Render.render_function(function)

    assert source =~ "fn draw_translate_impl<'a>("
    assert source =~ "canvas: &skia_safe::Canvas"
    assert source =~ "opts: generated_opts::TranslateOpts<'a>"
    assert source =~ "_raw_opts: &[(Atom, Term<'a>)]"
    assert source =~ "canvas.translate((opts.x, opts.y));"
    assert source =~ "Ok(())"
  end

  test "quoted maps configured Rust module alias calls" do
    function =
      RustQ.Meta.quoted(:atom_call,
        args: [],
        returns: quote(do: RustQ.Type.nif_result(atom())),
        rust_modules: %{[:Atoms] => [:atoms]},
        do:
          quote do
            Atoms.fill()
          end
      )

    source = RustQ.Rust.AST.Render.render_function(function)
    assert source =~ "atoms::fill()"
  end
end
