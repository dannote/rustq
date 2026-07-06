fn use_color(_color: &Color) -> NifResult<()> {
    Ok(())
}

fn run(color: Color, flag: u32) -> NifResult<()> {
    use_color(match flag {
        0 => &color,
        1 => &color,
    })?;
    Ok(())
}
