defmodule RustQ.Meta.GeneratedCase do
  @moduledoc """
  Test fixture module exercising `RustQ.Meta` type and function generation.
  """

  use RustQ.Meta

  alias RustQ.Type, as: R

  defmodule Canvas do
    @moduledoc false
    @type t :: term()
  end

  defmodule Click do
    @moduledoc """
    Fixture struct for click-event type lowering tests.
    """
    defstruct [:name]
  end

  defmodule Resize do
    @moduledoc """
    Fixture struct for resize-event type lowering tests.
    """
    defstruct [:width, :height]
  end

  defmodule Scroll do
    @moduledoc """
    Fixture struct for scroll-event type lowering tests.
    """
    defstruct [:dx, :dy]
  end

  @type mode :: :src_over | :multiply

  @type click :: %Click{name: String.t()}
  @type resize :: %Resize{width: R.u32(), height: R.u32()}
  @type scroll :: %Scroll{dx: R.f32(), dy: R.f32()}
  @type event :: click() | resize() | scroll()

  @type rect_opts :: %{
          required(:x) => R.f32(),
          required(:y) => R.f32(),
          required(:width) => R.f32(),
          required(:height) => R.f32(),
          optional(:fill) => term()
        }

  @type nested_opts :: %{
          required(:rect) => rect_opts(),
          optional(:label) => String.t()
        }

  @type callback :: R.raw(:"fn(u32) -> u32")

  @type callback_kind :: R.enum(one: [callback()], repeated: [callback()], disabled: [])

  @type callback_descriptor :: %{
          required(:id) => R.u32(),
          required(:callback) => callback(),
          required(:kind) => R.raw(:CallbackKind)
        }

  @spec draw_save(R.ref(Canvas.t())) :: R.nif_result(R.unit())
  defrust draw_save(canvas) do
    canvas.save()
    :ok
  end

  @spec decode_mode(atom()) :: R.nif_result(mode())
  defrust decode_mode(atom) do
    case atom do
      :src_over -> {:ok, BlendMode.SrcOver}
      :multiply -> {:ok, BlendMode.Multiply}
      _ -> {:error, :invalid_blend_mode}
    end
  end

  @spec draw_rect(R.ref(Canvas.t()), rect_opts(), term()) :: R.nif_result(R.unit())
  defrust draw_rect(canvas, opts, raw_opts) do
    rect = Rect.from_xywh(opts.x, opts.y, opts.width, opts.height)
    paint = unwrap!(decode_paint(opts.fill))
    unwrap!(apply_blend_mode(mut_ref(paint), raw_opts))
    canvas.draw_rect(ref(rect), ref(paint))
    :ok
  end

  @spec maybe_save(R.option(R.ref(Canvas.t()))) :: R.nif_result(R.unit())
  defrust maybe_save(canvas) do
    case canvas do
      nil -> :ok
      canvas -> canvas.save()
    end

    :ok
  end

  @spec unwrap_code(R.result(R.u32(), atom())) :: R.nif_result(R.u32())
  defrust unwrap_code(result) do
    case result do
      {:ok, value} -> {:ok, value + 0}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec handle_event(event()) :: R.nif_result(R.unit())
  defrust handle_event(event) do
    case event do
      %Click{name: name} -> log_click(name)
      %Resize{width: width, height: height} -> log_resize(width, height)
    end

    :ok
  end

  @spec nested_option(R.option(R.u32())) :: R.option(R.u32())
  defrust nested_option(value) do
    case value do
      nil ->
        nil

      value ->
        if value == 0 do
          nil
        else
          value
        end
    end
  end

  @spec nested_result(R.result(R.u32(), atom())) :: R.result(R.u32(), atom())
  defrust nested_result(result) do
    if is_ready() do
      case result do
        {:ok, value} -> {:ok, value + 0}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_ready}
    end
  end

  @spec nested_nif_result(R.result(R.u32(), atom())) :: R.nif_result(R.u32())
  defrust nested_nif_result(result) do
    if is_ready() do
      case result do
        {:ok, value} -> {:ok, value + 0}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_ready}
    end
  end
end
