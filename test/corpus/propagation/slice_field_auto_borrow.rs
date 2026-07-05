#[derive(Clone, Debug)]
pub struct Field {
    pub kind: Kind,
}

#[derive(Clone, Debug)]
pub enum Kind {
    One,
    Repeated,
}

fn use_kind(_kind: &Kind) -> NifResult<()> {
    Ok(())
}

fn run(fields: &[Field], index: usize) -> NifResult<()> {
    let field = fields.get(index).unwrap();
    use_kind(&field.kind)?;
    Ok(())
}
