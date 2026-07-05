pub struct Decoder<'a> {
    _bytes: &'a [u8],
}

impl<'a> Decoder<'a> {
    pub fn read_var_uint(&mut self) -> NifResult<u32> {
        todo!()
    }
}
