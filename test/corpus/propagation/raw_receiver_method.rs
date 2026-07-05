fn read_count(decoder: &mut Decoder<'_>) -> NifResult<u32> {
    let count = decoder.read_var_uint()?;
    Ok(count)
}
