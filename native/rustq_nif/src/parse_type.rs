use quote::quote;
use rustler::NifResult;
use syn::Type;

use crate::{parse_syn, path_from_parts};

pub(crate) fn parse_type_path_with_generics(
    path: Vec<String>,
    lifetimes: Vec<String>,
    generics: Vec<Type>,
) -> NifResult<Type> {
    let path = path_from_parts(path)?;
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

pub(crate) fn parse_type_unit(_term: rustler::Term) -> NifResult<Type> {
    parse_syn(quote!(()))
}

pub(crate) fn parse_type_raw(source: String) -> NifResult<Type> {
    syn::parse_str::<Type>(&source).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_type_slice(inner: Type) -> NifResult<Type> {
    parse_syn(quote!([#inner]))
}

pub(crate) fn parse_type_tuple(items: Vec<Type>) -> NifResult<Type> {
    if items.is_empty() {
        Err(rustler::Error::BadArg)
    } else {
        parse_syn(quote!((#(#items,)*)))
    }
}

pub(crate) fn parse_type_array(inner: Type, size: rustler::Term) -> NifResult<Type> {
    let size_source = if let Ok(size) = size.decode::<u64>() {
        size.to_string()
    } else {
        size.decode::<String>()?
    };

    let size: syn::Expr = syn::parse_str(&size_source).map_err(|_| rustler::Error::BadArg)?;
    parse_syn(quote!([#inner; #size]))
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
