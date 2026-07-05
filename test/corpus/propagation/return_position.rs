fn decode(atom: Atom) -> NifResult<u32> {
    atom.decode::<u32>()?
}

fn use_decode(atom: Atom) -> NifResult<u32> {
    let value = decode(atom)?;
    Ok(value)
}
