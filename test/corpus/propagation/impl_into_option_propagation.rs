fn decode_filter<'a>(_term: Term<'a>) -> NifResult<ImageFilter> {
    Ok(ImageFilter::default())
}

fn run<'a>(paint: &mut Paint, term: Term<'a>) -> NifResult<()> {
    paint.set_image_filter(decode_filter(term)?);
    Ok(())
}
