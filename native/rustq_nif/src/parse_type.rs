use quote::quote;
use rustler::NifResult;
use syn::Type;

use crate::parse_type;

pub(crate) fn parse_type_path(path: String, lifetimes: Vec<String>) -> NifResult<Type> {
    if lifetimes.is_empty() {
        parse_type(&path)
    } else {
        parse_type(&format!(
            "{}<{}>",
            path,
            lifetimes
                .into_iter()
                .map(|value| format!("'{}", value))
                .collect::<Vec<_>>()
                .join(", ")
        ))
    }
}

pub(crate) fn parse_type_ref(
    inner: Type,
    mutable: bool,
    lifetime: Option<String>,
) -> NifResult<Type> {
    let lifetime = lifetime
        .map(|value| format!("'{} ", value))
        .unwrap_or_default();
    let mutability = if mutable { "mut " } else { "" };
    parse_type(&format!("&{}{}{}", lifetime, mutability, quote!(#inner)))
}
