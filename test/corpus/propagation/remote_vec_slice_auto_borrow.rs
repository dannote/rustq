fn run() -> NifResult<Data> {
    let bytes = Vec::new();
    Ok(Data::new_copy(&bytes))
}
