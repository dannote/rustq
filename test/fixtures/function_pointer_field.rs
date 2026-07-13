type DecodeFn = fn(u32) -> u32;

struct DecodeField {
    decode: DecodeFn,
}
