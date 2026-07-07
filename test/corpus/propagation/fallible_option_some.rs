fn decode_rect<'a>(_term: Term<'a>) -> NifResult<Rect> {
    Ok(Rect::default())
}

fn maybe_rect<'a>(term: Term<'a>) -> NifResult<Option<Rect>> {
    Ok(Some(decode_rect(term)?))
}

fn use_rect_option(_rect: Option<Rect>) -> NifResult<()> {
    Ok(())
}

fn maybe_rect_from_option<'a>(term: Option<Term<'a>>) -> NifResult<()> {
    let rect = match term {
        Some(term) => Some(decode_rect(term)?),
        None => None,
    };
    use_rect_option(rect)
}
