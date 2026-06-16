use quote::{format_ident, quote};
use rustler::{Encoder, Env, NifResult, Term};
use syn::punctuated::Punctuated;
use syn::token::Comma;
use syn::{Arm, Expr, Field, File, FnArg, Item, Pat, Stmt, Type};

mod generated_ast;
mod parse;
mod template;

pub(crate) use parse::{parse_expr, parse_path, parse_syn, parse_type};
use template::{render_source, template_error};

use generated_ast::{atom, atom_key, atoms, is_nil, optional_map_get};
use generated_ast::{decode_arm, decode_enum_variant, decode_struct_field};
use generated_ast::{
    decode_ast_expr, decode_ast_item, decode_ast_pat, decode_ast_stmt, decode_ast_type,
};

#[rustler::nif(schedule = "DirtyCpu")]
fn parse<'a>(env: Env<'a>, source: String) -> NifResult<Term<'a>> {
    match syn::parse_file(&source) {
        Ok(_) => Ok(atoms::ok().encode(env)),
        Err(error) => Ok((atoms::error(), vec![template_error(error)]).encode(env)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn render<'a>(
    env: Env<'a>,
    source: String,
    bindings: Vec<(String, String)>,
    splices: Vec<(String, Vec<String>)>,
) -> NifResult<Term<'a>> {
    match render_source(&source, bindings, splices) {
        Ok(code) => Ok((atoms::ok(), code).encode(env)),
        Err(errors) => Ok((atoms::error(), errors).encode(env)),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn render_ast(ast: Term) -> NifResult<String> {
    let item = decode_ast_item(ast)?;
    Ok(prettyplease::unparse(&File {
        shebang: None,
        attrs: Vec::new(),
        items: vec![item],
    }))
}

// Handwritten item decoders that still need direct syn/Rustler glue.
// Temporary dogfood bridge helpers called by generated defrust decoders.
fn decode_item_list(term: Term) -> NifResult<Vec<Item>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_ast_item)
        .collect::<NifResult<Vec<Item>>>()
}

fn parse_item_use(tree: String) -> NifResult<syn::ItemUse> {
    syn::parse_str(&format!("use {tree};")).map_err(|_| rustler::Error::BadArg)
}

fn parse_item_module(
    name: syn::Ident,
    vis: syn::Visibility,
    items: Vec<Item>,
) -> NifResult<syn::ItemMod> {
    syn::parse2(quote!(#vis mod #name { #(#items)* })).map_err(|_| rustler::Error::BadArg)
}

fn parse_item_const(
    name: syn::Ident,
    ty: Type,
    expr: Expr,
    vis: syn::Visibility,
) -> NifResult<syn::ItemConst> {
    syn::parse2(quote!(#vis const #name: #ty = #expr;)).map_err(|_| rustler::Error::BadArg)
}

fn parse_macro_item(source: String) -> NifResult<Item> {
    syn::parse_str(&source).map_err(|_| rustler::Error::BadArg)
}

fn parse_item_function(
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
    let block =
        syn::parse2::<syn::Block>(quote!({ #(#stmts)* })).map_err(|_| rustler::Error::BadArg)?;

    if let Some(lifetime) = lifetime {
        let lifetime =
            syn::Lifetime::new(&format!("'{}", lifetime), proc_macro2::Span::call_site());
        syn::parse2(quote!(#vis fn #name <#lifetime> (#inputs) -> #returns #block))
            .map_err(|_| rustler::Error::BadArg)
    } else {
        syn::parse2(quote!(#vis fn #name (#inputs) -> #returns #block))
            .map_err(|_| rustler::Error::BadArg)
    }
}

fn parse_item_struct(
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

    syn::parse2(quote!(#(#derive)* #vis struct #name #generics { #(#fields)* }))
        .map_err(|_| rustler::Error::BadArg)
}

fn parse_struct_field(name: syn::Ident, ty: Type, vis: syn::Visibility) -> NifResult<Field> {
    let item: syn::ItemStruct = syn::parse2(quote!(struct __RustQ { #vis #name: #ty, }))
        .map_err(|_| rustler::Error::BadArg)?;
    item.fields.into_iter().next().ok_or(rustler::Error::BadArg)
}

fn decode_struct_field_list(term: Term) -> NifResult<Vec<Field>> {
    decode_list(term, decode_struct_field)
}

fn decode_enum_variant_list(term: Term) -> NifResult<Vec<syn::Variant>> {
    decode_list(term, decode_enum_variant)
}

fn parse_item_enum(
    name: syn::Ident,
    vis: syn::Visibility,
    derive: Vec<syn::Attribute>,
    variants: Vec<syn::Variant>,
) -> NifResult<syn::ItemEnum> {
    syn::parse2(quote!(#(#derive)* #vis enum #name { #(#variants),* }))
        .map_err(|_| rustler::Error::BadArg)
}

fn decode_type_list(term: Term) -> NifResult<Vec<Type>> {
    decode_list(term, decode_type)
}

fn parse_enum_variant(name: syn::Ident, tuple: Vec<Type>) -> NifResult<syn::Variant> {
    if tuple.is_empty() {
        syn::parse2(quote!(#name)).map_err(|_| rustler::Error::BadArg)
    } else {
        syn::parse2(quote!(#name(#(#tuple),*))).map_err(|_| rustler::Error::BadArg)
    }
}

// Rust syntax attribute/visibility decoders shared by handwritten and generated code.
fn decode_vis(term: Term) -> NifResult<syn::Visibility> {
    if is_nil(term)? {
        syn::parse2(quote!()).map_err(|_| rustler::Error::BadArg)
    } else {
        match term.atom_to_string()?.as_str() {
            "pub" => syn::parse2(quote!(pub)).map_err(|_| rustler::Error::BadArg),
            "crate" => syn::parse2(quote!(pub(crate))).map_err(|_| rustler::Error::BadArg),
            _ => Err(rustler::Error::BadArg),
        }
    }
}

fn decode_derive(term: Term) -> NifResult<Vec<syn::Attribute>> {
    let values = term
        .decode::<Vec<Term>>()?
        .into_iter()
        .map(atom_or_string)
        .collect::<NifResult<Vec<String>>>()?;

    if values.is_empty() {
        Ok(Vec::new())
    } else {
        let paths = values
            .into_iter()
            .map(|value| syn::parse_str::<syn::Path>(&value))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| rustler::Error::BadArg)?;
        Ok(vec![syn::parse_quote!(#[derive(#(#paths),*)])])
    }
}

// Collection decoders for generated AST nodes.
fn decode_list<T>(term: Term, decoder: fn(Term) -> NifResult<T>) -> NifResult<Vec<T>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decoder)
        .collect()
}

fn decode_stmt_list(term: Term) -> NifResult<Vec<Stmt>> {
    decode_list(term, decode_stmt)
}

fn decode_block(term: Term) -> NifResult<syn::Block> {
    let stmts = decode_stmt_list(term)?;
    syn::parse2::<syn::Block>(quote!({ #(#stmts)* })).map_err(|_| rustler::Error::BadArg)
}

fn decode_stmt(term: Term) -> NifResult<Stmt> {
    decode_ast_stmt(term)
}

fn decode_let_pattern(pat: Pat, mutable: bool) -> NifResult<proc_macro2::TokenStream> {
    if mutable {
        let Pat::Ident(mut pat_ident) = pat else {
            return Err(rustler::Error::BadArg);
        };
        pat_ident.mutability = Some(Default::default());
        Ok(quote!(#pat_ident))
    } else {
        Ok(quote!(#pat))
    }
}

fn parse_let_stmt(
    pat_tokens: proc_macro2::TokenStream,
    ty: Option<Type>,
    expr: Expr,
) -> NifResult<Stmt> {
    if let Some(ty) = ty {
        parse_syn::<Stmt>(quote!(let #pat_tokens: #ty = #expr;))
    } else {
        parse_syn::<Stmt>(quote!(let #pat_tokens = #expr;))
    }
}

fn decode_expr(term: Term) -> NifResult<Expr> {
    decode_ast_expr(term)
}

// syn parser helpers used as explicit Rusty-Elixir primitive boundaries.
fn parse_local_call(name: String, args: Vec<Expr>) -> NifResult<Expr> {
    if name.ends_with('!') {
        let source = format!(
            "{}({})",
            name,
            args.iter()
                .map(|arg| quote!(#arg).to_string())
                .collect::<Vec<_>>()
                .join(", ")
        );
        parse_expr(&source)
    } else {
        let name = format_ident!("{}", name);
        parse_syn::<Expr>(quote!(#name(#(#args),*)))
    }
}

fn decode_struct_literal_fields(term: Term) -> NifResult<Vec<proc_macro2::TokenStream>> {
    decode_token_field_list(term, decode_expr)
}

fn decode_arm_list(term: Term) -> NifResult<Vec<Arm>> {
    decode_list(term, decode_arm)
}

fn decode_atom_guard_arm(pat_term: Term, block: syn::Block) -> NifResult<Arm> {
    let name = format_ident!("{}", atom_key(pat_term, "name")?);
    parse_syn::<Arm>(quote!(value if value == atoms::#name() => #block,))
}

fn format_ident_value(name: String) -> proc_macro2::Ident {
    format_ident!("{}", name)
}

fn parse_ast_path(term: Term) -> NifResult<syn::Path> {
    parse_path(&path_parts(term.map_get(atom(term.get_env(), "parts")?)?)?)
}

fn string_field(term: Term, key: &str) -> NifResult<String> {
    term.map_get(atom(term.get_env(), key)?)?.decode()
}

fn decode_optional_field<T>(
    term: Term,
    key: &str,
    decoder: fn(Term) -> NifResult<T>,
) -> NifResult<Option<T>> {
    match optional_map_get(term, key)? {
        Some(value) if !is_nil(value)? => Ok(Some(decoder(value)?)),
        _ => Ok(None),
    }
}

fn decode_optional_type_field(term: Term, key: &str) -> NifResult<Option<Type>> {
    decode_optional_field(term, key, decode_type)
}

fn decode_optional_expr_field(term: Term, key: &str) -> NifResult<Option<Expr>> {
    decode_optional_field(term, key, decode_expr)
}

fn decode_pat_literal_value(term: Term) -> NifResult<Pat> {
    if let Ok(value) = term.decode::<String>() {
        return parse_syn::<Pat>(quote!(#value));
    }
    if term.is_atom() {
        let value = term.atom_to_string()?;
        return parse_syn::<Pat>(quote!(#value));
    }
    Err(rustler::Error::BadArg)
}

fn decode_pat(term: Term) -> NifResult<Pat> {
    decode_ast_pat(term)
}

fn decode_pat_atom_guard(_term: Term) -> NifResult<Pat> {
    Err(rustler::Error::BadArg)
}

fn decode_pat_list(term: Term) -> NifResult<Vec<Pat>> {
    decode_list(term, decode_pat)
}

fn decode_token_field_list<T: quote::ToTokens>(
    term: Term,
    decoder: fn(Term) -> NifResult<T>,
) -> NifResult<Vec<proc_macro2::TokenStream>> {
    term.decode::<Vec<(Term, Term)>>()?
        .into_iter()
        .map(|(name, value)| {
            let name = format_ident!("{}", atom_or_string(name)?);
            let value = decoder(value)?;
            Ok(quote!(#name: #value))
        })
        .collect()
}

fn decode_pat_struct_fields(term: Term) -> NifResult<Vec<proc_macro2::TokenStream>> {
    decode_token_field_list(term, decode_pat)
}

fn decode_expr_list(term: Term) -> NifResult<Vec<Expr>> {
    decode_list(term, decode_expr)
}

fn decode_literal_expr(term: Term) -> NifResult<Expr> {
    if let Ok(value) = term.decode::<bool>() {
        return if value {
            parse_syn::<Expr>(quote!(true))
        } else {
            parse_syn::<Expr>(quote!(false))
        };
    }
    if let Ok(value) = term.decode::<i64>() {
        return parse_syn::<Expr>(quote!(#value));
    }
    if let Ok(value) = term.decode::<f64>() {
        return parse_syn::<Expr>(quote!(#value));
    }
    if let Ok(value) = term.decode::<String>() {
        return parse_syn::<Expr>(quote!(#value));
    }
    Err(rustler::Error::BadArg)
}

fn keyword_args(term: Term) -> NifResult<Vec<(String, Type)>> {
    term.decode::<Vec<(Term, Term)>>()?
        .into_iter()
        .map(|(name, ty)| Ok((atom_or_string(name)?, decode_type(ty)?)))
        .collect()
}

fn path_parts(term: Term) -> NifResult<String> {
    Ok(term
        .decode::<Vec<Term>>()?
        .into_iter()
        .map(atom_or_string)
        .collect::<NifResult<Vec<String>>>()?
        .join("::"))
}

fn atom_or_string(term: Term) -> NifResult<String> {
    if term.is_atom() {
        term.atom_to_string()
    } else {
        term.decode::<String>()
    }
}

// Type decoding primitives retained until all type shapes are dogfooded.
fn decode_type(term: Term) -> NifResult<Type> {
    if let Ok(source) = term.decode::<String>() {
        return parse_type(&source);
    }

    decode_ast_type(term)
}

fn decode_lifetime_list(term: Term) -> NifResult<Vec<String>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(atom_or_string)
        .collect::<NifResult<Vec<String>>>()
}

fn parse_type_path(path: String, lifetimes: Vec<String>) -> NifResult<Type> {
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

fn parse_type_ref(inner: Type, mutable: bool, lifetime: Option<String>) -> NifResult<Type> {
    let lifetime = lifetime
        .map(|value| format!("'{} ", value))
        .unwrap_or_default();
    let mutability = if mutable { "mut " } else { "" };
    parse_type(&format!("&{}{}{}", lifetime, mutability, quote!(#inner)))
}

rustler::init!("Elixir.RustQ.Native");
