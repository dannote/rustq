macro_rules! as_u32 {
    ($term:expr) => {{
        $term.decode::<u32>()?
    }};
}

fn decode<'a>(term: Term<'a>) -> NifResult<u32> {
    as_u32!(term)
}
