fn maybe_size(_key: Atom) -> NifResult<Option<f32>> {
    Ok((atoms::some(), 12.0))
}

fn apply_size(key: Atom) -> NifResult<f32> {
    let value = 1.0;
    if let Some(size) = maybe_size(key)? {
        let value = size;
    }
    Ok(value)
}
