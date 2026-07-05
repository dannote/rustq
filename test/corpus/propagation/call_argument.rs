fn decode(atom: Atom) -> NifResult<u32> {
    atom.decode::<u32>()?
}

fn consume(value: u32) -> NifResult<()> {
    let _copy = value;
    Ok(())
}

fn run(atom: Atom) -> NifResult<()> {
    consume(decode(atom)?)?;
    Ok(())
}
