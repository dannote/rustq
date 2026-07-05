fn use_color(_color: &Color) -> NifResult<()> {
    Ok(())
}

fn run(color: Color, flag: bool) -> NifResult<()> {
    use_color(if flag { &color } else { &color })?;
    Ok(())
}
