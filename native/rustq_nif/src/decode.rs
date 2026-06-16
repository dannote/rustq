use quote::{format_ident, quote};
use rustler::{NifResult, Term};
use syn::{Arm, Expr, Field, Item, Pat, Stmt, Type};

use crate::generated_ast::{
    atom, atom_key, decode_arm, decode_ast_expr, decode_ast_item, decode_ast_pat, decode_ast_stmt,
    decode_ast_type, decode_enum_variant, decode_struct_field, is_nil, optional_map_get,
};
use crate::{parse_expr, parse_path, parse_syn, parse_type};

// Handwritten item decoders that still need direct syn/Rustler glue.
// Temporary dogfood bridge helpers called by generated defrust decoders.
pub(crate) fn decode_item_list(term: Term) -> NifResult<Vec<Item>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_ast_item)
        .collect::<NifResult<Vec<Item>>>()
}

pub(crate) fn decode_struct_field_list(term: Term) -> NifResult<Vec<Field>> {
    decode_list(term, decode_struct_field)
}

pub(crate) fn decode_enum_variant_list(term: Term) -> NifResult<Vec<syn::Variant>> {
    decode_list(term, decode_enum_variant)
}

pub(crate) fn decode_type_list(term: Term) -> NifResult<Vec<Type>> {
    decode_list(term, decode_type)
}

// Rust syntax attribute/visibility decoders shared by handwritten and generated code.
pub(crate) fn decode_vis(term: Term) -> NifResult<syn::Visibility> {
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

pub(crate) fn decode_derive(term: Term) -> NifResult<Vec<syn::Attribute>> {
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
pub(crate) fn decode_list<T>(term: Term, decoder: fn(Term) -> NifResult<T>) -> NifResult<Vec<T>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decoder)
        .collect()
}

pub(crate) fn decode_stmt_list(term: Term) -> NifResult<Vec<Stmt>> {
    decode_list(term, decode_stmt)
}

pub(crate) fn decode_block(term: Term) -> NifResult<syn::Block> {
    let stmts = decode_stmt_list(term)?;
    syn::parse2::<syn::Block>(quote!({ #(#stmts)* })).map_err(|_| rustler::Error::BadArg)
}

pub(crate) fn decode_stmt(term: Term) -> NifResult<Stmt> {
    decode_ast_stmt(term)
}

pub(crate) fn decode_let_pattern(pat: Pat, mutable: bool) -> NifResult<proc_macro2::TokenStream> {
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

pub(crate) fn parse_let_stmt(
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

pub(crate) fn decode_expr(term: Term) -> NifResult<Expr> {
    decode_ast_expr(term)
}

// syn parser helpers used as explicit Rusty-Elixir primitive boundaries.
pub(crate) fn parse_local_call(name: String, args: Vec<Expr>) -> NifResult<Expr> {
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

pub(crate) fn decode_struct_literal_fields(term: Term) -> NifResult<Vec<proc_macro2::TokenStream>> {
    decode_token_field_list(term, decode_expr)
}

pub(crate) fn decode_arm_list(term: Term) -> NifResult<Vec<Arm>> {
    decode_list(term, decode_arm)
}

pub(crate) fn decode_atom_guard_arm(pat_term: Term, block: syn::Block) -> NifResult<Arm> {
    let name = format_ident!("{}", atom_key(pat_term, "name")?);
    parse_syn::<Arm>(quote!(value if value == atoms::#name() => #block,))
}

pub(crate) fn format_ident_value(name: String) -> proc_macro2::Ident {
    format_ident!("{}", name)
}

pub(crate) fn parse_ast_path(term: Term) -> NifResult<syn::Path> {
    parse_path(&path_parts(term.map_get(atom(term.get_env(), "parts")?)?)?)
}

pub(crate) fn string_field(term: Term, key: &str) -> NifResult<String> {
    term.map_get(atom(term.get_env(), key)?)?.decode()
}

pub(crate) fn decode_optional_field<T>(
    term: Term,
    key: &str,
    decoder: fn(Term) -> NifResult<T>,
) -> NifResult<Option<T>> {
    match optional_map_get(term, key)? {
        Some(value) if !is_nil(value)? => Ok(Some(decoder(value)?)),
        _ => Ok(None),
    }
}

pub(crate) fn decode_optional_type_field(term: Term, key: &str) -> NifResult<Option<Type>> {
    decode_optional_field(term, key, decode_type)
}

pub(crate) fn decode_optional_expr_field(term: Term, key: &str) -> NifResult<Option<Expr>> {
    decode_optional_field(term, key, decode_expr)
}

pub(crate) fn decode_pat_literal_value(term: Term) -> NifResult<Pat> {
    if let Ok(value) = term.decode::<String>() {
        return parse_syn::<Pat>(quote!(#value));
    }
    if term.is_atom() {
        let value = term.atom_to_string()?;
        return parse_syn::<Pat>(quote!(#value));
    }
    Err(rustler::Error::BadArg)
}

pub(crate) fn decode_pat(term: Term) -> NifResult<Pat> {
    decode_ast_pat(term)
}

pub(crate) fn decode_pat_atom_guard(_term: Term) -> NifResult<Pat> {
    Err(rustler::Error::BadArg)
}

pub(crate) fn decode_pat_list(term: Term) -> NifResult<Vec<Pat>> {
    decode_list(term, decode_pat)
}

pub(crate) fn decode_token_field_list<T: quote::ToTokens>(
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

pub(crate) fn decode_pat_struct_fields(term: Term) -> NifResult<Vec<proc_macro2::TokenStream>> {
    decode_token_field_list(term, decode_pat)
}

pub(crate) fn decode_expr_list(term: Term) -> NifResult<Vec<Expr>> {
    decode_list(term, decode_expr)
}

pub(crate) fn decode_literal_expr(term: Term) -> NifResult<Expr> {
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

pub(crate) fn keyword_args(term: Term) -> NifResult<Vec<(String, Type)>> {
    term.decode::<Vec<(Term, Term)>>()?
        .into_iter()
        .map(|(name, ty)| Ok((atom_or_string(name)?, decode_type(ty)?)))
        .collect()
}

pub(crate) fn path_parts(term: Term) -> NifResult<String> {
    Ok(term
        .decode::<Vec<Term>>()?
        .into_iter()
        .map(atom_or_string)
        .collect::<NifResult<Vec<String>>>()?
        .join("::"))
}

pub(crate) fn atom_or_string(term: Term) -> NifResult<String> {
    if term.is_atom() {
        term.atom_to_string()
    } else {
        term.decode::<String>()
    }
}

// Type decoding primitives retained until all type shapes are dogfooded.
pub(crate) fn decode_type(term: Term) -> NifResult<Type> {
    if let Ok(source) = term.decode::<String>() {
        return parse_type(&source);
    }

    decode_ast_type(term)
}

pub(crate) fn decode_lifetime_list(term: Term) -> NifResult<Vec<String>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(atom_or_string)
        .collect::<NifResult<Vec<String>>>()
}
