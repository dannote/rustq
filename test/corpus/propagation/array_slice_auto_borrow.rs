fn use_values(_values: &[u32]) -> NifResult<()> {
    Ok(())
}

fn run() -> NifResult<()> {
    use_values(&[1, 2, 3])?;
    Ok(())
}
