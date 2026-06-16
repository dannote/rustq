use quote::quote;
use rustler::NifResult;
use syn::Type;

use crate::{parse_syn, parse_type};

pub(crate) fn parse_type_path_with_generics(
    path: String,
    lifetimes: Vec<String>,
    generics: Vec<Type>,
) -> NifResult<Type> {
    let path: syn::Path = syn::parse_str(&path).map_err(|_| rustler::Error::BadArg)?;
    let lifetimes = lifetimes
        .into_iter()
        .map(|value| syn::Lifetime::new(&format!("'{}", value), proc_macro2::Span::call_site()))
        .collect::<Vec<_>>();

    if lifetimes.is_empty() && generics.is_empty() {
        parse_syn(quote!(#path))
    } else {
        parse_syn(quote!(#path < #(#lifetimes,)* #(#generics),* >))
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

pub(crate) fn parse_type_generic(path: &str, args: Vec<Type>) -> NifResult<Type> {
    let path: syn::Path = syn::parse_str(path).map_err(|_| rustler::Error::BadArg)?;
    parse_syn(quote!(#path < #(#args),* >))
}
