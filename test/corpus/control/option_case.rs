fn fallback(value: Option<u32>) -> u32 {
    match value {
        None => 0,
        Some(value) => value,
    }
}
