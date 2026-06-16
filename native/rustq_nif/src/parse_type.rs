use quote::quote;
use rustler::NifResult;
use syn::Type;

use crate::parse_syn;

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
    match (mutable, lifetime) {
        (true, Some(lifetime)) => {
            let lifetime =
                syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
            parse_syn(quote!(& #lifetime mut #inner))
        }
        (true, None) => parse_syn(quote!(& mut #inner)),
        (false, Some(lifetime)) => {
            let lifetime =
                syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
            parse_syn(quote!(& #lifetime #inner))
        }
        (false, None) => parse_syn(quote!(& #inner)),
    }
}

pub(crate) fn parse_type_generic(path: &str, args: Vec<Type>) -> NifResult<Type> {
    let path: syn::Path = syn::parse_str(path).map_err(|_| rustler::Error::BadArg)?;
    parse_syn(quote!(#path < #(#args),* >))
}
