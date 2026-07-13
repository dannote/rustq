defmodule RustQ.Rustler do
  @moduledoc """
  Structural Rustler code generation.

  RustQ organizes Rustler generation by responsibility instead of repeating
  `nif_`, `term_`, or `resource_` prefixes on one large facade:

    * `RustQ.Rustler.Nif` — NIF wrappers, source-derived function metadata,
      Elixir stubs, `NifStruct` declarations, and `rustler::init!`
    * `RustQ.Rustler.Term` — safe term builders, decoders, encoders, and helpers
    * `RustQ.Rustler.Atom` — atom declarations, caches, decoders, and dispatch
    * `RustQ.Rustler.Opts` — keyword/options helpers and decoders
    * `RustQ.Rustler.Resource` — resource declarations and decoders
    * `RustQ.Rustler.Schema` — schema-driven Rustler generation
    * `RustQ.Rustler.Decode` — composable structural decode expressions

  Alias the modules used by a generator:

      alias RustQ.Rustler.{Atom, Nif, Term}

      rust "native/my_nif/src/generated_atoms.rs" do
        Atom.declaration([:ok, :error])
      end

      rust "native/my_nif/src/generated_nifs.rs" do
        Nif.wrappers_from_sources(nif_sources, schedule: :dirty_cpu)
      end

      generate "lib/my_app/native/generated_stubs.ex" do
        content(Nif.stubs_from_sources(nif_sources, MyApp.Native.GeneratedStubs))
      end

      rust "native/my_nif/src/generated_term_helpers.rs" do
        Term.helpers()
      end
  """
end
