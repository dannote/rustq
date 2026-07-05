fn classify(value: u32) -> u32 {
    match value {
        value if value == 0 => 1,
        _ => 2,
    }
}
