use quote::{format_ident, quote};
use rustler::NifResult;
use syn::parse::Parser;
use syn::punctuated::Punctuated;
use syn::token::Comma;
use syn::{Arm, Block, Expr, Field, FnArg, Item, Pat, Stmt, Type};

pub(crate) trait ParseSynTokens: Sized {
    fn parse_syn_tokens(tokens: proc_macro2::TokenStream) -> syn::Result<Self>;
}

macro_rules! impl_parse_syn_tokens {
    ($($type:ty),+ $(,)?) => {
        $(
            impl ParseSynTokens for $type {
                fn parse_syn_tokens(tokens: proc_macro2::TokenStream) -> syn::Result<Self> {
                    syn::parse2(tokens)
                }
            }
        )+
    };
}

impl_parse_syn_tokens!(
    Arm,
    Block,
    Expr,
    Stmt,
    Type,
    syn::ItemConst,
    syn::ItemEnum,
    syn::ItemFn,
    syn::ItemMod,
    syn::ItemStruct,
    syn::Variant,
);

impl ParseSynTokens for Pat {
    fn parse_syn_tokens(tokens: proc_macro2::TokenStream) -> syn::Result<Self> {
        Pat::parse_single.parse2(tokens)
    }
}

pub(crate) fn parse_syn<T: ParseSynTokens>(tokens: proc_macro2::TokenStream) -> NifResult<T> {
    T::parse_syn_tokens(tokens).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_type(source: &str) -> NifResult<Type> {
    syn::parse_str(source).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_path(source: &str) -> NifResult<syn::Path> {
    syn::parse_str(source).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn parse_expr(source: &str) -> NifResult<Expr> {
    syn::parse_str(source).map_err(|_| rustler::Error::BadArg)
}

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

pub(crate) fn parse_item_function(
    name: syn::Ident,
    vis: syn::Visibility,
    args: Vec<(String, Type)>,
    returns: Type,
    lifetime: Option<String>,
    stmts: Vec<Stmt>,
) -> NifResult<syn::ItemFn> {
    let inputs = args
        .into_iter()
        .map(|(name, ty)| {
            let ident = format_ident!("{}", name);
            syn::parse2::<FnArg>(quote!(#ident: #ty))
        })
        .collect::<Result<Punctuated<FnArg, Comma>, syn::Error>>()
        .map_err(|_| rustler::Error::BadArg)?;
    let block = parse_syn::<syn::Block>(quote!({ #(#stmts)* }))?;

    if let Some(lifetime) = lifetime {
        let lifetime =
            syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
        parse_syn(quote!(#vis fn #name <#lifetime> (#inputs) -> #returns #block))
    } else {
        parse_syn(quote!(#vis fn #name (#inputs) -> #returns #block))
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
