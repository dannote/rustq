defmodule RustQ.Atom do
  @moduledoc """
  Utilities for converting Elixir names into valid Rust identifiers and atoms.
  """

  @max_identifier_bytes 128

  @spec identifier!(atom() | String.t()) :: atom()
  def identifier!(value) when is_atom(value), do: value

  def identifier!(value) when is_binary(value) do
    if byte_size(value) <= @max_identifier_bytes and identifier?(value) do
      :erlang.binary_to_atom(value, :utf8)
    else
      raise ArgumentError, "unsafe atom identifier: #{inspect(value)}"
    end
  end

  @doc false
  @spec identifier?(String.t()) :: boolean()
  def identifier?(<<first, rest::binary>>) when first in ?A..?Z or first in ?a..?z,
    do: identifier_tail?(rest)

  def identifier?(<<"_", rest::binary>>), do: identifier_tail?(rest)
  def identifier?(""), do: false

  defp identifier_tail?(<<>>), do: true

  defp identifier_tail?(<<char, rest::binary>>)
       when char in ?A..?Z or char in ?a..?z or char in ?0..?9,
       do: identifier_tail?(rest)

  defp identifier_tail?(<<"_", rest::binary>>), do: identifier_tail?(rest)
  defp identifier_tail?(_invalid), do: false
end
