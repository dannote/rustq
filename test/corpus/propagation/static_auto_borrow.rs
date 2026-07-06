fn cached_atom(_cell: &OnceLock<Atom>) -> NifResult<()> {
    Ok(())
}

fn run() -> NifResult<()> {
    cached_atom(&GUID_ATOM)?;
    Ok(())
}
