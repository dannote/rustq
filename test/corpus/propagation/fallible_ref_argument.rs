fn decode<'a>(_term: Term<'a>) -> NifResult<Matrix> {
    Ok(Matrix::default())
}

fn consume(_matrix: &Matrix) -> NifResult<()> {
    Ok(())
}

fn run<'a>(term: Term<'a>) -> NifResult<()> {
    consume(&decode(term)?)
}
