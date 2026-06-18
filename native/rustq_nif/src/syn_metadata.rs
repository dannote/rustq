use quote::ToTokens;
use rustler::{Encoder, Env, NifResult, Term};
use syn::{Fields, FnArg, Item, ReturnType, Type, Visibility};

use crate::{atoms, template_error};

pub(crate) fn inspect_source<'a>(env: Env<'a>, source: String) -> NifResult<Term<'a>> {
    match syn::parse_file(&source) {
        Ok(file) => Ok((atoms::ok(), items(env, file.items)).encode(env)),
        Err(error) => Ok((atoms::error(), vec![template_error(error)]).encode(env)),
    }
}

pub(crate) fn enum_variants<'a>(
    env: Env<'a>,
    source: String,
    enum_name: String,
) -> NifResult<Term<'a>> {
    match syn::parse_file(&source) {
        Ok(file) => {
            let variants = file.items.into_iter().find_map(|item| match item {
                Item::Enum(item) if item.ident == enum_name => Some(
                    item.variants
                        .into_iter()
                        .map(|variant| variant.ident.to_string())
                        .collect::<Vec<_>>(),
                ),
                _ => None,
            });

            match variants {
                Some(variants) => Ok((atoms::ok(), variants).encode(env)),
                None => Ok((atoms::error(), format!("enum {enum_name} not found")).encode(env)),
            }
        }
        Err(error) => Ok((atoms::error(), vec![template_error(error)]).encode(env)),
    }
}

fn items<'a>(env: Env<'a>, items: Vec<Item>) -> Vec<Term<'a>> {
    items
        .into_iter()
        .filter_map(|item| item_term(env, item))
        .collect()
}

fn item_term<'a>(env: Env<'a>, item: Item) -> Option<Term<'a>> {
    match item {
        Item::Enum(item) => Some(
            (
                "enum",
                item.ident.to_string(),
                visibility(&item.vis),
                item.variants
                    .into_iter()
                    .map(|variant| variant.ident.to_string())
                    .collect::<Vec<_>>(),
            )
                .encode(env),
        ),
        Item::Struct(item) => Some(
            (
                "struct",
                item.ident.to_string(),
                visibility(&item.vis),
                fields(item.fields),
            )
                .encode(env),
        ),
        Item::Fn(item) => Some(
            (
                "function",
                item.sig.ident.to_string(),
                visibility(&item.vis),
                item.sig
                    .inputs
                    .into_iter()
                    .map(function_arg)
                    .collect::<Vec<_>>(),
                return_type(item.sig.output),
            )
                .encode(env),
        ),
        _ => None,
    }
}

fn fields(fields: Fields) -> Vec<(Option<String>, String)> {
    fields
        .into_iter()
        .map(|field| {
            (
                field.ident.map(|ident| ident.to_string()),
                type_string(field.ty),
            )
        })
        .collect()
}

fn function_arg(arg: FnArg) -> (Option<String>, String) {
    match arg {
        FnArg::Receiver(receiver) => (
            Some("self".to_string()),
            receiver.to_token_stream().to_string(),
        ),
        FnArg::Typed(arg) => (pat_name(*arg.pat), type_string(*arg.ty)),
    }
}

fn pat_name(pat: syn::Pat) -> Option<String> {
    match pat {
        syn::Pat::Ident(ident) => Some(ident.ident.to_string()),
        _ => None,
    }
}

fn return_type(output: ReturnType) -> Option<String> {
    match output {
        ReturnType::Default => None,
        ReturnType::Type(_, ty) => Some(type_string(*ty)),
    }
}

fn type_string(ty: Type) -> String {
    ty.to_token_stream().to_string()
}

fn visibility(vis: &Visibility) -> &'static str {
    match vis {
        Visibility::Public(_) => "public",
        _ => "private",
    }
}
