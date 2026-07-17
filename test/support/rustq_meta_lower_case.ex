defmodule RustQ.Meta.LowerCase do
  @moduledoc false

  alias RustQ.Meta.Type
  alias RustQ.Rust.AST

  defmodule Arg do
    @moduledoc false
    defstruct [:name, :type, :syn]
  end

  def unit_type, do: %Type{kind: :unit, rust: "()", ast: %AST.TypeUnit{}}

  def self_arg,
    do: %Arg{
      name: "self",
      type: %Type{kind: :ref, rust: "&Self", ast: %AST.TypeRaw{source: "&Self"}},
      syn: nil
    }

  def rect_arg,
    do: %Arg{
      name: "rect",
      type: %Type{kind: :type, rust: "Rect", ast: %AST.TypeRaw{source: "Rect"}},
      syn: nil
    }
end
