fn use_term<'a>(_term: Term<'a>) -> NifResult<()> {
    Ok(())
}

fn decode_first<'a>(args: Vec<Term<'a>>) -> NifResult<String> {
    let text = args
        .first()
        .ok_or(rustler::Error::BadArg)?
        .decode::<String>()?;
    Ok(text)
}

fn deref_first<'a>(args: Vec<Term<'a>>) -> NifResult<()> {
    let term = *args.first().ok_or(rustler::Error::BadArg)?;
    use_term(term)
}

fn decode_map_field<'a>(term: Term<'a>) -> NifResult<String> {
    let value = term.map_get(atoms::value())?.decode::<String>()?;
    Ok(value)
}
