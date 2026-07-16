defmodule RustQ.Meta.Core.Call do
  @moduledoc false

  @kernel_functions [
    :+,
    :-,
    :*,
    :/,
    :==,
    :!=,
    :<,
    :<=,
    :>,
    :>=,
    :and,
    :or,
    :not,
    :div,
    :rem,
    :in,
    :..,
    :abs,
    :min,
    :max,
    :byte_size,
    :length,
    :map_size,
    :elem,
    :put_elem,
    :tuple_size,
    :is_nil
  ]

  defstruct [:module, :function, :args, :meta, :source]

  @type t :: %__MODULE__{
          module: module(),
          function: atom(),
          args: [Macro.t()],
          meta: keyword(),
          source: Macro.t()
        }

  @spec normalize(Macro.t()) :: {:ok, t()} | :unsupported
  def normalize({{:., _, [{:__aliases__, _, parts}, function]}, meta, args} = source)
      when is_list(parts) and is_atom(function) and is_list(args) do
    {:ok,
     %__MODULE__{
       module: Module.concat(parts),
       function: function,
       args: args,
       meta: meta,
       source: source
     }}
  end

  def normalize({function, meta, args} = source)
      when function in @kernel_functions and is_list(args) do
    {:ok,
     %__MODULE__{
       module: Kernel,
       function: function,
       args: args,
       meta: meta,
       source: source
     }}
  end

  def normalize(_ast), do: :unsupported
end
