defmodule RustQ.Config do
  @moduledoc """
  Small DSL for declaring RustQ-generated files in `rustq.exs`.

      import RustQ.Config

      generate :term_helpers, "native/generated_term_helpers.rs" do
        build fn ->
          RustQ.render!("__splice_items!();", "generated_term_helpers.rs",
            splice: [items: RustQ.Rustler.term_helpers()]
          )
        end
      end
  """

  defmacro rustq(do: block) do
    quote do
      RustQ.Config.__start__()

      try do
        unquote(block)
        [generated: RustQ.Config.__finish__()]
      after
        RustQ.Config.__delete__()
      end
    end
  end

  defmacro generate(name, path, do: block) do
    quote do
      RustQ.Config.__start_target__(unquote(name), unquote(path))
      unquote(block)
      RustQ.Config.__finish_target__()
      RustQ.Config.__manifest__()
    end
  end

  defmacro generate(path, do: block) do
    quote do
      RustQ.Config.__start_target__(
        Path.basename(unquote(path), Path.extname(unquote(path))),
        unquote(path)
      )

      unquote(block)
      RustQ.Config.__finish_target__()
      RustQ.Config.__manifest__()
    end
  end

  defmacro build(fun) do
    quote do
      RustQ.Config.__put_target_option__(:build, unquote(fun))
    end
  end

  defmacro content(value) do
    quote do
      RustQ.Config.__put_target_option__(:content, unquote(value))
    end
  end

  def __start__, do: Process.put(:rustq_config_targets, [])
  def __delete__, do: Process.delete(:rustq_config_targets)

  def __finish__ do
    Process.get(:rustq_config_targets, [])
  end

  def __manifest__, do: [generated: Process.get(:rustq_config_targets, [])]

  def __start_target__(name, path) do
    __ensure_started__()
    Process.put(:rustq_config_target, {name, [path: path]})
  end

  def __ensure_started__ do
    unless Process.get(:rustq_config_targets) do
      __start__()
    end
  end

  def __put_target_option__(key, value) do
    {name, target} = Process.get(:rustq_config_target)
    Process.put(:rustq_config_target, {name, Keyword.put(target, key, value)})
  end

  def __finish_target__ do
    {name, target} = Process.delete(:rustq_config_target)
    targets = Process.get(:rustq_config_targets, [])
    Process.put(:rustq_config_targets, [{name, target} | targets])
    :ok
  end
end
