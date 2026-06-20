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

  alias RustQ.Config.State

  defmacro __using__(_opts) do
    quote do
      import RustQ.Config
    end
  end

  defmacro rustq(do: block) do
    quote do
      State.start()

      try do
        unquote(block)
        [generated: State.finish()]
      after
        State.delete()
      end
    end
  end

  defmacro generate(name, path, do: block) do
    quote do
      State.start_target(unquote(name), unquote(path))
      unquote(block)
      State.finish_target()
      State.manifest()
    end
  end

  defmacro generate(path, do: block) do
    quote do
      State.start_target(
        Path.basename(unquote(path), Path.extname(unquote(path))),
        unquote(path)
      )

      unquote(block)
      State.finish_target()
      State.manifest()
    end
  end

  defmacro rust(name, path, do: block) do
    items = block_items(block)

    quote do
      State.put_rust_items(unquote(name), unquote(path), unquote(items))
    end
  end

  defmacro rust(path, do: block) do
    items = block_items(block)

    quote do
      path = unquote(path)

      State.put_rust_items(
        State.target_name(path),
        path,
        unquote(items)
      )
    end
  end

  defmacro rust_items(name, path, do: block) do
    items = block_items(block)

    quote do
      State.put_rust_items(unquote(name), unquote(path), unquote(items))
    end
  end

  defmacro rust_items(name, path, opts) do
    quote do
      State.put_target(
        unquote(name),
        unquote(path),
        build: fn -> State.render_rust_items(unquote(path), unquote(opts)) end
      )

      State.manifest()
    end
  end

  defmacro rust_items(path, do: block) do
    items = block_items(block)

    quote do
      path = unquote(path)

      State.put_rust_items(
        State.target_name(path),
        path,
        unquote(items)
      )
    end
  end

  defmacro rust_items(path, opts) do
    quote do
      path = unquote(path)

      State.put_target(
        State.target_name(path),
        path,
        build: fn -> State.render_rust_items(path, unquote(opts)) end
      )

      State.manifest()
    end
  end

  defmacro require_file(path) do
    quote do
      path = unquote(path)
      module = State.module_from_path(path)

      if module == nil or not Code.ensure_loaded?(module) do
        Code.require_file(path)
      end

      State.manifest()
    end
  end

  defmacro render(template, opts \\ []) do
    quote do
      State.put_target_option(
        :build,
        fn -> State.render(unquote(template), unquote(opts)) end
      )
    end
  end

  defmacro build(fun) do
    quote do
      State.put_target_option(:build, unquote(fun))
    end
  end

  defmacro content(value) do
    quote do
      State.put_target_option(:content, unquote(value))
    end
  end

  defmacro from_module(module) do
    quote do
      unquote(module).__rustq_items__()
    end
  end

  defp block_items({:__block__, _meta, items}), do: items
  defp block_items(item), do: item
end
