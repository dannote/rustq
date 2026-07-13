defmodule RustQ.Rust.Syntax do
  @moduledoc """
  Struct modules used by the `RustQ.Rust` string/iodata builder layer.
  """
end

defmodule RustQ.Rust.Block do
  @moduledoc """
  Represents a Rust block body assembled from statement or expression fragments.
  """

  defstruct lines: []

  @type t :: %__MODULE__{lines: [term()]}
end

defmodule RustQ.Rust.Const do
  @moduledoc """
  Represents a Rust `const` declaration built with `RustQ.Rust.const/4`.
  """
  defstruct [:name, :type, :value, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          value: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end

defmodule RustQ.Rust.EnumDecl do
  @moduledoc """
  Represents a Rust enum declaration built with `RustQ.Rust.enum/2`.
  """
  defstruct [:name, attrs: [], variants: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          variants: [term()],
          vis: atom() | String.t() | nil
        }
end

defmodule RustQ.Rust.Field do
  @moduledoc """
  Represents a Rust struct field built with `RustQ.Rust.field/3`.
  """
  defstruct [:name, :type, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end

defmodule RustQ.Rust.ShorthandField do
  @moduledoc """
  Represents a shorthand Rust struct literal field such as `name,`.
  """
  defstruct [:name]

  @type t :: %__MODULE__{name: atom() | String.t()}
end

defmodule RustQ.Rust.Fragment do
  @moduledoc """
  Represents a raw Rust fragment validated or spliced by RustQ.
  """
  defstruct [:kind, :code]

  @type t :: %__MODULE__{kind: atom(), code: iodata()}
end

defmodule RustQ.Rust.Function do
  @moduledoc """
  Represents a Rust function declaration built with `RustQ.Rust.fn/2`.
  """
  defstruct [
    :name,
    args: [],
    attrs: [],
    body: "",
    returns: nil,
    vis: nil,
    generics: [],
    where: []
  ]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          args: [term()],
          attrs: [term()],
          body: iodata(),
          returns: term(),
          vis: atom() | String.t() | nil,
          generics: [term()],
          where: [term()]
        }
end

defmodule RustQ.Rust.Impl do
  @moduledoc """
  Represents a Rust `impl` block built with `RustQ.Rust.impl/2`.
  """
  defstruct [:target, items: [], trait: nil]

  @type t :: %__MODULE__{target: term(), items: [term()], trait: term() | nil}
end

defmodule RustQ.Rust.ModDecl do
  @moduledoc """
  Represents a Rust module declaration built with `RustQ.Rust.mod/2`.
  """
  defstruct [:name, attrs: [], items: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          items: [term()],
          vis: atom() | String.t() | nil
        }
end

defmodule RustQ.Rust.Struct do
  @moduledoc """
  Represents a Rust struct declaration built with `RustQ.Rust.struct/2`.
  """
  defstruct [:name, attrs: [], fields: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          attrs: [term()],
          fields: [term()],
          vis: atom() | String.t() | nil
        }
end

defmodule RustQ.Rust.TypeAlias do
  @moduledoc """
  Represents a Rust type alias built with `RustQ.Rust.type_alias/3`.
  """
  defstruct [:name, :type, attrs: [], vis: nil]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          type: term(),
          attrs: [term()],
          vis: atom() | String.t() | nil
        }
end

defmodule RustQ.Rust.Use do
  @moduledoc """
  Represents a Rust `use` declaration built with `RustQ.Rust.use/2`.
  """
  defstruct [:path, vis: nil]

  @type t :: %__MODULE__{path: term(), vis: atom() | String.t() | nil}
end
