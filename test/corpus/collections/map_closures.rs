fn increment(value: u32) -> u32 {
    value + 1
}

fn map_named(values: Vec<u32>) -> Vec<u32> {
    values.into_iter().map(increment).collect::<Vec<u32>>()
}

fn map_block(values: Vec<u32>) -> Vec<u32> {
    values
        .into_iter()
        .map(|value| {
            let doubled = value * 2;
            doubled + 1
        })
        .collect::<Vec<u32>>()
}
