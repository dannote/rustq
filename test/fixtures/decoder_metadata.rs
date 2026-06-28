use rustler::NifResult;

pub struct Decoder<'a> {
    data: &'a [u8],
}

impl<'a> Decoder<'a> {
    pub fn read_var_int64(&mut self) -> NifResult<i64> {
        Ok(0)
    }
}
