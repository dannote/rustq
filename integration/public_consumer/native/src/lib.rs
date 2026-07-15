use rustler::{NifResult, Term};

include!("generated.rs");

pub fn increment_values(values: Vec<u32>) -> Vec<u32> {
    increment_all(values)
}

pub fn decode_value(term: Term<'_>) -> NifResult<u32> {
    decode_input(term)?.value.decode()
}
