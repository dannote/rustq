fn use_bytes(_bytes: &[u8]) -> NifResult<()> {
    Ok(())
}

fn run() -> NifResult<()> {
    let bytes = Vec::new();
    use_bytes(&bytes)
}
