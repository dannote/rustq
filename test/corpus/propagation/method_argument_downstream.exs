defmodule RustQ.Corpus.Propagation.MethodArgumentDownstream do
  @moduledoc "Infer let propagation from downstream receiver method arguments."

  use RustQ.Meta, rust_sources: ["test/fixtures/method_arg_propagation.rs"]

  alias RustQ.Type, as: R

  @spec decode_mode(atom()) :: R.nif_result(R.path(:BlendMode))
  defrust decode_mode(_atom) do
    {:ok, BlendMode.SrcOver}
  end

  @spec run(R.ref(R.path({:skia_safe, :Canvas})), atom()) :: R.nif_result(R.unit())
  defrust run(canvas, atom) do
    vertices = Vertices.default()
    paint = Paint.default()
    mode = decode_mode(atom)
    canvas.draw_vertices(vertices, mode, paint)
    :ok
  end
end
