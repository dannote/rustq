defmodule RustQ.Atom do
  @moduledoc """
  Utilities for converting Elixir names into valid Rust identifiers and atoms.
  """

  @max_identifier_bytes 128
  @identifier_regex ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec identifier!(atom() | String.t()) :: atom()
  def identifier!(value) when is_atom(value), do: value

  def identifier!(value) when is_binary(value) do
    if byte_size(value) <= @max_identifier_bytes and Regex.match?(@identifier_regex, value) do
      :erlang.binary_to_atom(value, :utf8)
    else
      raise ArgumentError, "unsafe atom identifier: #{inspect(value)}"
    end
  end
end
