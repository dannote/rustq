defmodule RustQ.Test do
  @moduledoc """
  ExUnit helpers for RustQ-generated `defrust` and `defnif` modules.

  Use this module from consumer tests:

      defmodule MyApp.NativeTest do
        use RustQ.Test, async: true

        test "generates and exports the native boundary" do
          assert_defrust MyApp.Native, :sum_impl, "fn sum_impl"
          assert_defnif MyApp.Native, :sum, 1, ~r/fn sum.*Vec<f64>/
          assert_rust_valid MyApp.Native
        end
      end

  String expectations perform substring matches; regex expectations use
  `Regex.match?/2`. Assertions render one generated function at a time so
  failures remain focused.
  """

  alias RustQ.Rust
  alias RustQ.Rust.AST

  defmacro __using__(opts) do
    quote do
      use ExUnit.Case, unquote(opts)
      import RustQ.Test
    end
  end

  @doc "Asserts that a generated module's complete Rust source matches a string or regex."
  defmacro assert_rust(module, expected) do
    quote do
      module = unquote(module)
      expected = unquote(expected)
      source = RustQ.Test.source!(module)

      ExUnit.Assertions.assert(
        RustQ.Test.source_matches?(source, expected),
        RustQ.Test.failure_message(module, nil, expected, source)
      )
    end
  end

  @doc "Asserts that a named `defrust`/`defrustp` function matches a string or regex."
  defmacro assert_defrust(module, function, expected) do
    quote do
      module = unquote(module)
      function = unquote(function)
      expected = unquote(expected)
      source = RustQ.Test.function_source!(module, function)

      ExUnit.Assertions.assert(
        RustQ.Test.source_matches?(source, expected),
        RustQ.Test.failure_message(module, function, expected, source)
      )
    end
  end

  @doc "Asserts that a `defnif` is exported, marked as a Rustler NIF, and matches generated Rust."
  defmacro assert_defnif(module, function, arity, expected) do
    quote do
      module = unquote(module)
      function = unquote(function)
      arity = unquote(arity)
      expected = unquote(expected)

      ExUnit.Assertions.assert(
        function_exported?(module, function, arity),
        "expected #{inspect(module)}.#{function}/#{arity} to be exported"
      )

      ExUnit.Assertions.assert(
        RustQ.Test.nif?(module, function),
        "expected generated #{inspect(module)}.#{function} to carry #[rustler::nif]"
      )

      source = RustQ.Test.function_source!(module, function)

      ExUnit.Assertions.assert(
        RustQ.Test.source_matches?(source, expected),
        RustQ.Test.failure_message(module, function, expected, source)
      )
    end
  end

  @doc "Asserts that all generated Rust items for a module parse as valid Rust."
  defmacro assert_rust_valid(module) do
    quote do
      module = unquote(module)
      source = RustQ.Test.source!(module)

      ExUnit.Assertions.assert(
        RustQ.valid?(source, "#{inspect(module)}.rs"),
        "expected generated Rust for #{inspect(module)} to parse:\n#{source}"
      )
    end
  end

  @doc "Returns a generated module's complete Rust source or raises."
  @spec source!(module()) :: String.t()
  def source!(module) when is_atom(module) do
    if function_exported?(module, :__rustq_source__, 0) do
      module.__rustq_source__()
    else
      raise ArgumentError, "#{inspect(module)} does not expose __rustq_source__/0"
    end
  end

  @doc "Renders one generated Rust function by name or raises."
  @spec function_source!(module(), atom()) :: String.t()
  def function_source!(module, function) when is_atom(module) and is_atom(function) do
    module
    |> functions!()
    |> Enum.find(&match?(%AST.Function{name: ^function}, &1))
    |> case do
      %AST.Function{} = item -> Rust.render(item)
      nil -> raise ArgumentError, "#{inspect(module)} has no generated function #{function}"
    end
  end

  @doc "Returns whether a generated function carries the Rustler NIF attribute."
  @spec nif?(module(), atom()) :: boolean()
  def nif?(module, function) when is_atom(module) and is_atom(function) do
    module
    |> functions!()
    |> Enum.any?(fn
      %AST.Function{name: ^function, attrs: attrs} ->
        Enum.any?(attrs, &match?(%AST.Attribute{path: [:rustler, :nif]}, &1))

      _item ->
        false
    end)
  end

  @doc false
  def source_matches?(source, expected) when is_binary(expected), do: source =~ expected
  def source_matches?(source, %Regex{} = expected), do: Regex.match?(expected, source)

  @doc false
  def failure_message(module, function, expected, source) do
    target = if function, do: "#{inspect(module)}.#{function}", else: inspect(module)
    "expected generated Rust for #{target} to match #{inspect(expected)}:\n#{source}"
  end

  defp functions!(module) do
    if function_exported?(module, :__rustq_asts__, 0) do
      module.__rustq_asts__()
    else
      raise ArgumentError, "#{inspect(module)} does not expose __rustq_asts__/0"
    end
  end
end
