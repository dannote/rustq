defmodule RustQ.Type do
  @moduledoc """
  Built-in Rust/Rustler type vocabulary for `RustQ.Meta.defrust/2` specs.

  Prefer ordinary Elixir types when they fit. `RustQ.Meta` maps built-ins such
  as `atom()`, `term()`, `boolean()`, `integer()`, `float()`, and `binary()` to
  Rust/Rustler types. Use ordinary remote types for external Rust paths where
  possible: `SkiaSafe.Canvas.t()` renders as `skia_safe::Canvas`, and
  `GeneratedOpts.OvalOpts.t(R.lifetime(:a))` renders as
  `generated_opts::OvalOpts<'a>`. Use this module where Rust needs extra
  precision or syntax that Elixir types cannot express cleanly: fixed-width
  numbers, references, lifetimes, slices, `NifResult`, `Vec`, and unit.

      alias RustQ.Type, as: R

      @spec draw(R.ref(SkiaSafe.Canvas.t()), R.f32(), R.f32()) :: R.nif_result(R.unit())
      defrust draw(canvas, x, y) do
        canvas.translate({x, y})
        :ok
      end

      @spec decode_mode(atom()) :: R.nif_result(Mode.t())
      defrust decode_mode(atom) do
        # atom() maps to Rustler Atom
      end

  The functions with matching names are marker helpers for non-typespec macro
  contexts and for the reserved built-in names (`R.atom()`, `R.bool()`,
  `R.term()`). They are not runtime APIs.
  """

  @typedoc "Rust `()`; represented as `:ok`/unit-ish data in Elixir specs."
  @type unit :: :ok

  # `bool`, `atom`, and `term` are built-in Elixir type names and cannot be
  # redefined as remote types. RustQ still accepts `R.bool()`, `R.atom()`, and
  # `R.term()` in defrust specs by reading the marker call AST.
  @typedoc "Rust `u8`."
  @type u8 :: 0..255

  @typedoc "Rust `u32`."
  @type u32 :: non_neg_integer()

  @typedoc "Rust `i64`."
  @type i64 :: integer()

  @typedoc "Rust `f32`."
  @type f32 :: float()

  @typedoc "Rust `f64`."
  @type f64 :: float()

  @typedoc "Rust string slice `&str`."
  @type str :: binary()

  @typedoc "Rust shared reference `&T`."
  @type ref(t) :: t

  @typedoc "Rust mutable reference `&mut T`."
  @type mut_ref(t) :: t

  @typedoc "Rust `Option<T>`."
  @type option(t) :: nil | t

  @typedoc "Rust `Result<Ok, Error>`."
  @type result(ok, error) :: {:ok, ok} | {:error, error}

  @typedoc "Rustler `NifResult<T>`."
  @type nif_result(t) :: {:ok, t} | {:error, nif_error()}

  @typedoc "Rust `Vec<T>`."
  @type vec(t) :: [t]

  @typedoc "Rustler NIF error marker."
  @type nif_error :: atom()

  @typedoc "Low-level explicit Rust path marker. Prefer ordinary remote types such as `GeneratedOpts.OvalOpts.t(...)` when possible."
  @type path(parts) :: {parts, term()}

  @typedoc "Low-level explicit Rust path marker with options such as `R.lifetime(:a)`. Prefer ordinary remote types when possible."
  @type path(parts, opts) :: {parts, opts, term()}

  @typedoc "Rust lifetime marker for external remote types and low-level `R.path/2`."
  @type lifetime(name) :: {name, term()}

  @typedoc "Rust slice reference `&[T]`."
  @type slice(t) :: {t, term()}

  @typedoc "Raw Rust type fragment marker for syntax Elixir typespecs cannot model. Prefer structural markers such as `R.slice/1` when possible."
  @type raw(name) :: {name, term()}

  @typedoc "Native Rust enum marker with descriptor lookup metadata."
  @type native_enum(rust_type, opts) :: atom() | {rust_type, opts}

  def atom, do: type_only!()
  def bool, do: type_only!()
  def f32, do: type_only!()
  def f64, do: type_only!()
  def i8, do: type_only!()
  def i16, do: type_only!()
  def i32, do: type_only!()
  def i64, do: type_only!()
  def isize, do: type_only!()
  def str, do: type_only!()
  def term, do: type_only!()
  def u8, do: type_only!()
  def u16, do: type_only!()
  def u32, do: type_only!()
  def u64, do: type_only!()
  def usize, do: type_only!()
  def unit, do: type_only!()

  def path(_parts), do: type_only!()
  def path(_parts, _opts), do: type_only!()
  def lifetime(_name), do: type_only!()
  def slice(_type), do: type_only!()
  def raw(_name), do: type_only!()
  def native_enum(_rust_type, _opts), do: type_only!()

  def ref(_type), do: type_only!()
  def mut_ref(_type), do: type_only!()
  def option(_type), do: type_only!()
  def vec(_type), do: type_only!()
  def result(_ok, _error), do: type_only!()
  def nif_result(_type), do: type_only!()

  defp type_only! do
    raise "RustQ.Type functions are typespec markers for RustQ.Meta; they are not runtime functions"
  end
end
