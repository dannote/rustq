fn add_one(value: u32) -> u32 {
    value + 1
}

fn double(value: u32) -> u32 {
    value * 2
}

fn run(value: u32) -> u32 {
    value.add_one().double()
}
