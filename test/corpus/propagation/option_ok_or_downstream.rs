fn maybe_path() -> Option<Path> {
    Some(Path::default())
}

fn use_path(_path: &mut Path) -> NifResult<()> {
    Ok(())
}

fn run() -> NifResult<()> {
    let mut path = maybe_path().ok_or(rustler::Error::BadArg)?;
    use_path(&mut path)
}
