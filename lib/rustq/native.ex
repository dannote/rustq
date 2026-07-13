defmodule RustQ.Native do
  @moduledoc """
  Native Rust source metadata used by bindings and generators.

  `RustQ.Native.Ref`, `RustQ.Native.Descriptor`, and
  `RustQ.Native.EnumDescriptor` describe resolved Rust items. The private NIF
  bridge that powers parsing and rendering is intentionally not part of this
  public API.
  """
end
