defmodule RustQ.Config do
  @moduledoc """
  DSL for declaring generated RustQ files in `rustq.exs`.

  A manifest is ordinary Elixir. It can require helper modules, declare generated
  Rust item files, or provide custom render/build functions.

      use RustQ.Config

      alias RustQ.Rustler

      require_file "lib/my_app/codegen/schema.ex"

      rust "native/my_nif/src/generated_term_helpers.rs" do
        Rustler.term_helpers()
      end

      rust "native/my_nif/src/generated_schema.rs" do
        MyApp.Codegen.Schema.rust_items()
      end

  Run `mix rustq.gen` to write files and `mix rustq.gen --check` in CI to fail
  when checked-in generated files are stale.
  """
  defmacro __using__(_opts) do
    quote do
      import RustQ.Config
    end
  end

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

  defmacro rust(name, path, do: block) do
    items = block_items(block)

    quote do
      RustQ.Config.__put_rust_items__(unquote(name), unquote(path), unquote(items))
    end
  end

  defmacro rust(path, do: block) do
    items = block_items(block)

    quote do
      path = unquote(path)
      RustQ.Config.__put_rust_items__(RustQ.Config.__target_name__(path), path, unquote(items))
    end
  end

  defmacro rust_items(name, path, do: block) do
    items = block_items(block)

    quote do
      RustQ.Config.__put_rust_items__(unquote(name), unquote(path), unquote(items))
    end
  end

  defmacro rust_items(name, path, opts) do
    quote do
      RustQ.Config.__put_target__(
        unquote(name),
        unquote(path),
        build: fn -> RustQ.Config.__render_rust_items__(unquote(path), unquote(opts)) end
      )

      RustQ.Config.__manifest__()
    end
  end

  defmacro rust_items(path, do: block) do
    items = block_items(block)

    quote do
      path = unquote(path)
      RustQ.Config.__put_rust_items__(RustQ.Config.__target_name__(path), path, unquote(items))
    end
  end

  defmacro rust_items(path, opts) do
    quote do
      path = unquote(path)

      RustQ.Config.__put_target__(
        RustQ.Config.__target_name__(path),
        path,
        build: fn -> RustQ.Config.__render_rust_items__(path, unquote(opts)) end
      )

      RustQ.Config.__manifest__()
    end
  end

  defmacro require_file(path) do
    quote do
      path = unquote(path)
      module = RustQ.Config.__module_from_path__(path)

      if module == nil or not Code.ensure_loaded?(module) do
        Code.require_file(path)
      end

      RustQ.Config.__manifest__()
    end
  end

  defmacro render(template, opts \\ []) do
    quote do
      RustQ.Config.__put_target_option__(
        :build,
        fn -> RustQ.Config.__render__(unquote(template), unquote(opts)) end
      )
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

  defmacro from_module(module) do
    quote do
      unquote(module).__rustq_items__()
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

  def __put_target__(name, path, opts) do
    __ensure_started__()
    targets = Process.get(:rustq_config_targets, [])
    Process.put(:rustq_config_targets, [{name, Keyword.put(opts, :path, path)} | targets])
  end

  def __put_rust_items__(name, path, items) do
    __put_target__(
      name,
      path,
      build: fn -> RustQ.Config.__render_rust_items__(path, items: items) end
    )

    __manifest__()
  end

  def __target_name__(path) do
    path
    |> Path.basename(Path.extname(path))
    |> String.replace_prefix("generated_", "")
  end

  def __module_from_path__(path) do
    segments =
      path
      |> Path.rootname()
      |> String.split("/")
      |> Enum.drop_while(&(&1 in ["lib", "test", "support"]))
      |> Enum.map(&Macro.camelize/1)

    case segments do
      [] -> nil
      segments -> Module.concat(segments)
    end
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

  def __render_rust_items__(path, opts) do
    items = opts |> Keyword.fetch!(:items) |> List.wrap() |> List.flatten()
    opts = Keyword.put(opts, :splice, items: items)

    __render__("__rq_items!();", Keyword.put(opts, :filename, Path.basename(path)))
  end

  def __render__(template, opts) do
    filename = Keyword.get(opts, :filename, "rustq_generated.rs")

    render_opts =
      opts
      |> Keyword.delete(:filename)
      |> expand_preamble()

    RustQ.render!(template, filename, render_opts)
  end

  defp block_items({:__block__, _meta, items}), do: items
  defp block_items(item), do: item

  defp expand_preamble(opts) do
    case Keyword.get(opts, :preamble, :rustq) do
      :rustq ->
        Keyword.put(
          opts,
          :preamble,
          "// This file is generated by RustQ. Do not edit by hand.\n\n"
        )

      _other ->
        opts
    end
  end
end
