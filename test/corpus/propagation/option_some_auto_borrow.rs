fn use_color_option(_color: Option<&Color>) -> NifResult<()> {
    Ok(())
}

fn use_tuple_option(_tuple: Option<(&Color, i64)>) -> NifResult<()> {
    Ok(())
}

fn run(color: Color) -> NifResult<()> {
    use_color_option(Some(&color))?;
    use_tuple_option(Some((&color, 1)))?;
    Ok(())
}
