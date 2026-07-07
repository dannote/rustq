fn decode_mode(_atom: Atom) -> NifResult<BlendMode> {
    Ok(BlendMode::SrcOver)
}

fn run(canvas: &skia_safe::Canvas, atom: Atom) -> NifResult<()> {
    let vertices = vertices::default();
    let paint = Paint::default();
    let mode = decode_mode(atom)?;
    canvas.draw_vertices(&vertices, mode, &paint);
    Ok(())
}
