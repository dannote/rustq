fn make_term<'a>() -> Term<'a> {
    0
}

fn decode_value<'a>() -> NifResult<Term<'a>> {
    Ok(make_term())
}

fn run<'a>(values: &mut Vec<Term<'a>>) -> NifResult<()> {
    values.push(decode_value()?);
    Ok(())
}
