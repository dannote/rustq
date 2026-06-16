use quote::quote;
use rustler::NifResult;
use syn::{Expr, Field, FnArg, Item, Stmt, Type};

use crate::parse_syn;

pub(crate) fn parse_item_use(tree: String) -> NifResult<syn::ItemUse> {
    syn::parse_str(&format!("use {tree};")).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_item_module(
    name: syn::Ident,
    vis: syn::Visibility,
    items: Vec<Item>,
) -> NifResult<syn::ItemMod> {
    parse_syn(quote!(#vis mod #name { #(#items)* }))
}

pub(crate) fn parse_item_const(
    name: syn::Ident,
    ty: Type,
    expr: Expr,
    vis: syn::Visibility,
) -> NifResult<syn::ItemConst> {
    parse_syn(quote!(#vis const #name: #ty = #expr;))
}

pub(crate) fn parse_macro_item(source: String) -> NifResult<Item> {
    syn::parse_str(&source).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_item_function_args(
    name: syn::Ident,
    vis: syn::Visibility,
    args: Vec<FnArg>,
    returns: Type,
    lifetime: Option<String>,
    stmts: Vec<Stmt>,
) -> NifResult<syn::ItemFn> {
    let inputs = args;
    let block = parse_syn::<syn::Block>(quote!({ #(#stmts)* }))?;

    if let Some(lifetime) = lifetime {
        let lifetime =
            syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
        parse_syn(quote!(#vis fn #name <#lifetime> (#(#inputs),*) -> #returns #block))
    } else {
        parse_syn(quote!(#vis fn #name (#(#inputs),*) -> #returns #block))
    }
}

pub(crate) fn parse_item_struct(
    name: syn::Ident,
    vis: syn::Visibility,
    derive: Vec<syn::Attribute>,
    lifetime: Option<String>,
    fields: Vec<Field>,
) -> NifResult<syn::ItemStruct> {
    let generics = if let Some(lifetime) = lifetime {
        let lifetime =
            syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
        quote!(<#lifetime>)
    } else {
        quote!()
    };

    parse_syn(quote!(#(#derive)* #vis struct #name #generics { #(#fields)* }))
}

pub(crate) fn parse_function_arg(name: syn::Ident, ty: Type) -> NifResult<FnArg> {
    parse_syn(quote!(#name: #ty))
}

pub(crate) fn parse_struct_field(
    name: syn::Ident,
    ty: Type,
    vis: syn::Visibility,
) -> NifResult<Field> {
    let item: syn::ItemStruct = parse_syn(quote!(struct __RustQ { #vis #name: #ty, }))?;
    item.fields.into_iter().next().ok_or(rustler::Error::BadArg)
}

pub(crate) fn parse_item_enum(
    name: syn::Ident,
    vis: syn::Visibility,
    derive: Vec<syn::Attribute>,
    variants: Vec<syn::Variant>,
) -> NifResult<syn::ItemEnum> {
    parse_syn(quote!(#(#derive)* #vis enum #name { #(#variants),* }))
}

pub(crate) fn parse_enum_variant(name: syn::Ident, tuple: Vec<Type>) -> NifResult<syn::Variant> {
    if tuple.is_empty() {
        parse_syn(quote!(#name))
    } else {
        parse_syn(quote!(#name(#(#tuple),*)))
    }
}
