use std::sync::OnceLock;

pub static GUID_ATOM: OnceLock<Atom> = OnceLock::new();

fn cached_atom(cell: &OnceLock<Atom>) -> NifResult<()> {
    Ok(())
}
