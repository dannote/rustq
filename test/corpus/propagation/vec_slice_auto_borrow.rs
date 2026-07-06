fn use_bytes(_bytes: &[u8]) -> NifResult<()> {
    Ok(())
}

fn run(bytes: Vec<u8>) -> NifResult<()> {
    use_bytes(&bytes)
}
