fn use_color(_color: &Color) -> NifResult<()> {
    Ok(())
}

fn run(color: Color, flag: u32) -> NifResult<()> {
    use_color(match flag {
        0i64 => &color,
        1i64 => &color,
    })?;
    Ok(())
}
