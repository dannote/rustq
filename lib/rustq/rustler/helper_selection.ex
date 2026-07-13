defmodule RustQ.Rustler.HelperSelection do
  @moduledoc false

  @spec names(keyword(), [atom()]) :: [atom()]
  def names(opts, default_names) do
    opts
    |> Keyword.get(:include, default_names)
    |> include_names(default_names)
    |> Kernel.--(List.wrap(Keyword.get(opts, :exclude, [])))
  end

  defp include_names(:all, default_names), do: default_names
  defp include_names(names, _default_names), do: List.wrap(names)
end
