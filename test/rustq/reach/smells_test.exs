defmodule RustQ.Reach.SmellsTest do
  use ExUnit.Case, async: true

  alias RustQ.Reach.Smells.BlocklessDefrustmod
  alias RustQ.Reach.Smells.DefrustMissingSpec
  alias RustQ.Reach.Smells.DynamicRawRustEscape
  alias RustQ.Reach.Smells.LowLevelControlFlow
  alias RustQ.Reach.Smells.RawRustEscape
  alias RustQ.Reach.Smells.TrivialDefrustWrapper

  test "detects large raw Rust escapes" do
    source = ~S'''
    defmodule Sample.RawEscape do
      def build do
        RustQ.Rust.item("""
        fn generated() {
            do_work();
        }
        """)
      end
    end
    '''

    assert [%{kind: :rustq_large_raw_rust_escape}] = run_check(RawRustEscape, source)
  end

  test "ignores tiny raw Rust escapes" do
    source = """
    defmodule Sample.TinyRawEscape do
      def build do
        RustQ.Rust.AST.Builder.macro_item("rustler::atoms! { ok }")
      end
    end
    """

    assert [] = run_check(RawRustEscape, source)
  end

  test "detects dynamic raw Rust escapes" do
    source = """
    defmodule Sample.DynamicRawEscape do
      def build(source), do: raw_expr!(source)
    end
    """

    assert [%{kind: :rustq_dynamic_raw_rust_escape}] = run_check(DynamicRawRustEscape, source)
  end

  test "allows literal raw Rust escapes" do
    source = """
    defmodule Sample.LiteralRawEscape do
      def build, do: raw_expr!(\"unsafe { value }\")
    end
    """

    assert [] = run_check(DynamicRawRustEscape, source)
  end

  test "detects defrust declarations without specs" do
    source = """
    defmodule Sample.MissingSpec do
      use RustQ.Meta

      defrust decode(term) do
        term
      end
    end
    """

    assert [%{kind: :rustq_defrust_missing_spec}] = run_check(DefrustMissingSpec, source)
  end

  test "accepts typed defrust declarations" do
    source = """
    defmodule Sample.TypedDefrust do
      use RustQ.Meta
      alias RustQ.Type, as: R

      @spec decode(R.term()) :: R.nif_result(R.term())
      defrust decode(term) do
        {:ok, term}
      end
    end
    """

    assert [] = run_check(DefrustMissingSpec, source)
  end

  test "detects low-level control flow in defrust bodies" do
    source = """
    defmodule Sample.LowLevel do
      use RustQ.Meta

      defrust decode(value) do
        return!(value)
      end
    end
    """

    assert [%{kind: :rustq_low_level_control_flow}] = run_check(LowLevelControlFlow, source)
  end

  test "detects blockless defrustmod declarations" do
    source = """
    defmodule Sample.BlocklessMod do
      use RustQ.Meta

      defrustmod(GeneratedOpts, as: :generated_opts)
    end
    """

    assert [%{kind: :rustq_blockless_defrustmod}] = run_check(BlocklessDefrustmod, source)
  end

  test "ignores block-form defrustmod declarations" do
    source = """
    defmodule Sample.BlockMod do
      use RustQ.Meta

      defrustmod Helpers, as: :helpers do
        defrust identity(value) do
          value
        end
      end
    end
    """

    assert [] = run_check(BlocklessDefrustmod, source)
  end

  test "detects trivial defrust wrappers" do
    source = """
    defmodule Sample.Wrapper do
      use RustQ.Meta

      defrust skip(decoder) do
        unwrap!(decoder.read_var_int64())
        :ok
      end
    end
    """

    assert [%{kind: :rustq_trivial_defrust_wrapper}] = run_check(TrivialDefrustWrapper, source)
  end

  test "does not flag meaningful defrust bodies as trivial wrappers" do
    source = """
    defmodule Sample.NotWrapper do
      use RustQ.Meta

      defrust skip(decoder, remaining) do
        if remaining == 0 do
          :ok
        else
          skip(decoder, remaining - 1)
        end
      end
    end
    """

    assert [] = run_check(TrivialDefrustWrapper, source)
  end

  defp run_check(check, source) do
    path = temp_source!(source)
    project = Reach.Project.from_sources([path], source_only: true, plugins: [])
    check.run(project)
  end

  defp temp_source!(source) do
    dir = Path.join(System.tmp_dir!(), "rustq-reach-smells-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    path
  end
end
