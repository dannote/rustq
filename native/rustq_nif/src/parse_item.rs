use quote::{format_ident, quote, ToTokens};
use rustler::{NifResult, Term};
use syn::{Expr, Field, FnArg, Item, Stmt, Type};

use crate::{parse_syn, path_from_parts};

pub(crate) fn parse_item_use(tree: String) -> NifResult<syn::ItemUse> {
    syn::parse_str(&format!("use {tree};")).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_item_use_path(parts: Vec<String>) -> NifResult<syn::ItemUse> {
    let path = path_from_parts(parts)?;
    parse_syn(quote!(use #path;))
}

pub(crate) fn parse_item_use_group(
    base: Vec<String>,
    names: Vec<String>,
) -> NifResult<syn::ItemUse> {
    let base = path_from_parts(base)?;
    let names = names
        .into_iter()
        .map(|name| format_ident!("{}", name))
        .collect::<Vec<_>>();

    parse_syn(quote!(use #base::{#(#names),*};))
}

pub(crate) fn parse_item_module(
    name: syn::Ident,
    vis: syn::Visibility,
    items: Vec<Item>,
) -> NifResult<syn::ItemMod> {
    parse_syn(quote!(#vis mod #name { #(#items)* }))
}

pub(crate) fn parse_item_impl(
    target: Type,
    trait_path: Option<Type>,
    items: Vec<Item>,
    attrs: Vec<syn::Attribute>,
    lifetimes: Vec<String>,
) -> NifResult<syn::ItemImpl> {
    let item_tokens = items
        .into_iter()
        .map(|item| match item {
            Item::Fn(function) => quote!(#function),
            other => quote!(#other),
        })
        .collect::<Vec<_>>();

    let lifetime_tokens = lifetimes
        .into_iter()
        .map(|name| syn::Lifetime::new(&format!("'{}", name), proc_macro2::Span::call_site()))
        .collect::<Vec<_>>();

    match (trait_path, lifetime_tokens.is_empty()) {
        (Some(trait_path), true) => {
            parse_syn(quote!(#(#attrs)* impl #trait_path for #target { #(#item_tokens)* }))
        }
        (Some(trait_path), false) => parse_syn(
            quote!(#(#attrs)* impl<#(#lifetime_tokens),*> #trait_path for #target { #(#item_tokens)* }),
        ),
        (None, true) => parse_syn(quote!(#(#attrs)* impl #target { #(#item_tokens)* })),
        (None, false) => {
            parse_syn(quote!(#(#attrs)* impl<#(#lifetime_tokens),*> #target { #(#item_tokens)* }))
        }
    }
}

pub(crate) fn parse_item_const(
    name: syn::Ident,
    ty: Type,
    expr: Expr,
    vis: syn::Visibility,
) -> NifResult<syn::ItemConst> {
    parse_syn(quote!(#vis const #name: #ty = #expr;))
}

pub(crate) fn parse_item_static(
    name: syn::Ident,
    ty: Type,
    expr: Expr,
    mutable: bool,
    vis: syn::Visibility,
) -> NifResult<syn::ItemStatic> {
    if mutable {
        parse_syn(quote!(#vis static mut #name: #ty = #expr;))
    } else {
        parse_syn(quote!(#vis static #name: #ty = #expr;))
    }
}

pub(crate) fn parse_item_type(
    name: syn::Ident,
    ty: Type,
    vis: syn::Visibility,
) -> NifResult<syn::ItemType> {
    parse_syn(quote!(#vis type #name = #ty;))
}

pub(crate) fn parse_macro_item(source: String) -> NifResult<Item> {
    syn::parse_str(&source).map_err(|_| rustler::Error::BadArg)
}

pub(crate) struct MacroItemArg {
    name: proc_macro2::Ident,
    value: Option<String>,
}

impl ToTokens for MacroItemArg {
    fn to_tokens(&self, tokens: &mut proc_macro2::TokenStream) {
        let name = &self.name;

        if let Some(value) = &self.value {
            tokens.extend(quote!(#name = #value));
        } else {
            tokens.extend(quote!(#name));
        }
    }
}

pub(crate) fn decode_macro_item_arg_list(term: Term) -> NifResult<Vec<MacroItemArg>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_macro_item_arg)
        .collect()
}

fn decode_macro_item_arg(term: Term) -> NifResult<MacroItemArg> {
    if let Ok((name, value)) = term.decode::<(Term, String)>() {
        return Ok(MacroItemArg {
            name: format_ident!("{}", crate::atom_or_string(name)?),
            value: Some(value),
        });
    }

    Ok(MacroItemArg {
        name: format_ident!("{}", crate::atom_or_string(term)?),
        value: None,
    })
}

pub(crate) fn parse_macro_item_call(path: syn::Path, args: Vec<MacroItemArg>) -> NifResult<Item> {
    parse_syn(quote!(#path! { #(#args),* }))
}

pub(crate) fn parse_item_function_args(
    name: syn::Ident,
    vis: syn::Visibility,
    args: Vec<FnArg>,
    returns: Type,
    lifetime: Option<String>,
    stmts: Vec<Stmt>,
    attrs: Vec<syn::Attribute>,
) -> NifResult<syn::ItemFn> {
    let inputs = args;
    let block = parse_syn::<syn::Block>(quote!({ #(#stmts)* }))?;

    if let Some(lifetime) = lifetime {
        let lifetime =
            syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
        parse_syn(quote!(#(#attrs)* #vis fn #name <#lifetime> (#(#inputs),*) -> #returns #block))
    } else {
        parse_syn(quote!(#(#attrs)* #vis fn #name (#(#inputs),*) -> #returns #block))
    }
}

pub(crate) fn parse_item_struct(
    name: syn::Ident,
    vis: syn::Visibility,
    derive: Vec<syn::Attribute>,
    lifetime: Option<String>,
    fields: Vec<Field>,
    attrs: Vec<syn::Attribute>,
) -> NifResult<syn::ItemStruct> {
    let generics = if let Some(lifetime) = lifetime {
        let lifetime =
            syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
        quote!(<#lifetime>)
    } else {
        quote!()
    };

    parse_syn(quote!(#(#derive)* #(#attrs)* #vis struct #name #generics { #(#fields)* }))
}

pub(crate) fn parse_function_arg(name: syn::Ident, ty: Type) -> NifResult<FnArg> {
    parse_syn(quote!(#name: #ty))
}

pub(crate) fn parse_function_receiver(mutable: bool) -> NifResult<FnArg> {
    if mutable {
        parse_syn(quote!(&mut self))
    } else {
        parse_syn(quote!(&self))
    }
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
    attrs: Vec<syn::Attribute>,
) -> NifResult<syn::ItemEnum> {
    parse_syn(quote!(#(#derive)* #(#attrs)* #vis enum #name { #(#variants),* }))
}

pub(crate) fn parse_enum_variant(name: syn::Ident, tuple: Vec<Type>) -> NifResult<syn::Variant> {
    if tuple.is_empty() {
        parse_syn(quote!(#name))
    } else {
        parse_syn(quote!(#name(#(#tuple),*)))
    }
}
