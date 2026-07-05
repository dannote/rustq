fn compute(left: u32, right: u32) -> u32 {
    bor(band(left + right, 255), 1)
}
