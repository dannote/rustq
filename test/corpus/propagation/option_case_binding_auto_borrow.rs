fn maybe_color() -> Option<Color> {
    None
}

fn use_color(_color: &Color) -> NifResult<()> {
    Ok(())
}

fn run() -> NifResult<()> {
    if let Some(color) = maybe_color() {
        use_color(&color)?;
    }
    Ok(())
}

fn run_as_ref(color: Option<Color>) -> NifResult<()> {
    if let Some(color) = color.as_ref() {
        use_color(color)?;
    }
    Ok(())
}
