defmodule RustQ.NativeRef do
  @moduledoc """
  Reference to a Rust native item used by code generators.

  A native ref names the Rust package plus a target/member pair, for example
  `skia-safe::Canvas::draw_rect`. Package is optional for local or
  caller-scoped references.
  """

  defstruct [:package, :target, :member]

  @type t :: %__MODULE__{
          package: String.t() | nil,
          target: String.t(),
          member: String.t()
        }

  @doc "Builds a native reference."
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(target, member, opts \\ []) when is_binary(target) and is_binary(member) do
    %__MODULE__{package: Keyword.get(opts, :package), target: target, member: member}
  end

  @doc "Formats a native reference as a Rust path."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{package: nil, target: target, member: member}),
    do: "#{target}::#{member}"

  def format(%__MODULE__{package: package, target: target, member: member}) do
    "#{crate_name(package)}::#{target}::#{member}"
  end

  defp crate_name(package), do: String.replace(package, "-", "_")
end
