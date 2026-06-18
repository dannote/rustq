use quote::{format_ident, quote, ToTokens};
use rustler::{NifResult, Term};
use syn::{Arm, Expr, Field, Item, Pat, Stmt, Type};

use crate::generated_ast::{
    atom, atom_key, decode_arm, decode_ast_expr, decode_ast_item, decode_ast_pat, decode_ast_stmt,
    decode_ast_type, decode_enum_variant, decode_function_arg, decode_struct_field, is_nil,
    optional_map_get, struct_name,
};
use crate::{parse_expr, parse_path, parse_syn, parse_type, path_from_parts};

// Primitive-boundary inventory:
// - Forever primitive: Rustler Term APIs, atom/string conversion, map/list traversal.
// - Generic glue: list/optional decoding and typed named-field collection.
// - Dogfood candidates: keyword_args, path_parts, decode_lifetime_list once iterator lowering exists.
// - Parse assembly belongs in parse.rs, parse_item.rs, or parse_type.rs, not here.
// Temporary dogfood bridge helpers called by generated defrust decoders.
pub(crate) fn decode_item_list(term: Term) -> NifResult<Vec<Item>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_ast_item)
        .collect::<NifResult<Vec<Item>>>()
}

pub(crate) fn decode_function_arg_list(term: Term) -> NifResult<Vec<syn::FnArg>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_function_arg_value)
        .collect()
}

fn decode_function_arg_value(term: Term) -> NifResult<syn::FnArg> {
    match decode_function_arg(term) {
        Ok(arg) => Ok(arg),
        Err(_) => {
            let (name, ty) = term.decode::<(Term, Term)>()?;
            let name = format_ident!("{}", atom_or_string(name)?);
            let ty = decode_type(ty)?;
            crate::parse_function_arg(name, ty)
        }
    }
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
    let paths = crate::generated_ast::decode_derive_path_list(term)?;

    if paths.is_empty() {
        Ok(Vec::new())
    } else {
        Ok(vec![syn::parse_quote!(#[derive(#(#paths),*)])])
    }
}

enum AttributeArg {
    Ident(proc_macro2::Ident),
    NameValueString(proc_macro2::Ident, String),
}

impl ToTokens for AttributeArg {
    fn to_tokens(&self, tokens: &mut proc_macro2::TokenStream) {
        match self {
            AttributeArg::Ident(ident) => tokens.extend(quote!(#ident)),
            AttributeArg::NameValueString(ident, value) => tokens.extend(quote!(#ident = #value)),
        }
    }
}

fn decode_attribute_value(term: Term) -> NifResult<String> {
    if let Ok(value) = term.decode::<String>() {
        Ok(value)
    } else {
        atom_or_string(term)
    }
}

pub(crate) fn decode_attribute_list(term: Term) -> NifResult<Vec<syn::Attribute>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_attribute)
        .collect()
}

fn decode_attribute(term: Term) -> NifResult<syn::Attribute> {
    let path = path_from_parts(decode_string_list(
        term.map_get(atom(term.get_env(), "path")?)?,
    )?)?;
    let arg_term = term.map_get(atom(term.get_env(), "args")?)?;

    if let Ok((tag, value)) = arg_term.decode::<(Term, Term)>() {
        if atom_or_string(tag)? == "value" {
            let value = decode_attribute_value(value)?;
            return parse_syn(quote!(#[#path = #value]));
        }
    }

    let args = decode_attribute_args(arg_term)?;

    if args.is_empty() {
        parse_syn(quote!(#[#path]))
    } else {
        parse_syn(quote!(#[#path(#(#args),*)]))
    }
}

fn decode_attribute_args(term: Term) -> NifResult<Vec<AttributeArg>> {
    if let Ok(args) = term.decode::<Vec<(Term, Term)>>() {
        return args
            .into_iter()
            .map(|(key, value)| {
                Ok(AttributeArg::NameValueString(
                    format_ident!("{}", atom_or_string(key)?),
                    decode_attribute_value(value)?,
                ))
            })
            .collect();
    }

    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(|value| {
            Ok(AttributeArg::Ident(format_ident!(
                "{}",
                atom_or_string(value)?
            )))
        })
        .collect()
}

pub(crate) fn decode_derive_path_terms(term: Term) -> NifResult<Vec<Term>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(|term| {
            if struct_name(term).ok().as_deref() == Some("Elixir.RustQ.Rust.AST.Derive") {
                term.map_get(atom(term.get_env(), "paths")?)?
                    .decode::<Vec<Term>>()
            } else {
                Ok(vec![term])
            }
        })
        .collect::<NifResult<Vec<Vec<Term>>>>()
        .map(|terms| terms.into_iter().flatten().collect())
}

pub(crate) fn decode_path_value(term: Term) -> NifResult<syn::Path> {
    let parts = if let Ok(parts) = term.decode::<Vec<Term>>() {
        parts
            .into_iter()
            .map(atom_or_string)
            .collect::<NifResult<Vec<String>>>()?
    } else {
        vec![atom_or_string(term)?]
    };

    path_from_parts(parts)
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

pub(crate) fn decode_optional_block_field(
    term: Term,
    field: &str,
) -> NifResult<Option<syn::Block>> {
    let value = term.map_get(atom(term.get_env(), field)?)?;
    let values = value.decode::<Vec<Term>>()?;

    if values.is_empty() {
        Ok(None)
    } else {
        Ok(Some(decode_block(value)?))
    }
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

pub(crate) fn parse_let_else_stmt(pat: Pat, expr: Expr, else_block: syn::Block) -> NifResult<Stmt> {
    parse_syn::<Stmt>(quote!(let #pat = #expr else #else_block;))
}

pub(crate) fn parse_assign_stmt(target: Expr, expr: Expr) -> NifResult<Stmt> {
    parse_syn::<Stmt>(quote!(#target = #expr;))
}

pub(crate) fn parse_return_stmt(expr: Expr) -> NifResult<Stmt> {
    parse_syn::<Stmt>(quote!(return #expr;))
}

pub(crate) fn parse_if_let_stmt(
    pattern: Pat,
    expr: Expr,
    then_block: syn::Block,
    else_block: Option<syn::Block>,
) -> NifResult<Stmt> {
    if let Some(else_block) = else_block {
        parse_syn::<Stmt>(quote!(if let #pattern = #expr #then_block else #else_block))
    } else {
        parse_syn::<Stmt>(quote!(if let #pattern = #expr #then_block))
    }
}

pub(crate) fn parse_for_stmt(pattern: Pat, expr: Expr, body: syn::Block) -> NifResult<Stmt> {
    parse_syn::<Stmt>(quote!(for #pattern in #expr #body))
}

pub(crate) fn decode_expr(term: Term) -> NifResult<Expr> {
    decode_ast_expr(term)
}

// syn parser helpers used as explicit Rusty-Elixir primitive boundaries.
pub(crate) fn parse_path_call_expr(
    path: syn::Path,
    args: Vec<Expr>,
    generics: Vec<Type>,
) -> NifResult<Expr> {
    if generics.is_empty() {
        parse_syn::<Expr>(quote!(#path(#(#args),*)))
    } else {
        parse_syn::<Expr>(quote!(#path::<#(#generics),*>(#(#args),*)))
    }
}

pub(crate) fn parse_method_call_expr(
    receiver: Expr,
    method: proc_macro2::Ident,
    args: Vec<Expr>,
    generics: Vec<Type>,
) -> NifResult<Expr> {
    if generics.is_empty() {
        parse_syn::<Expr>(quote!(#receiver.#method(#(#args),*)))
    } else {
        parse_syn::<Expr>(quote!(#receiver.#method::<#(#generics),*>(#(#args),*)))
    }
}

pub(crate) fn parse_field_expr(receiver: Expr, field: Term) -> NifResult<Expr> {
    if let Ok(index) = field.decode::<u32>() {
        let index = syn::Index::from(index as usize);
        return parse_syn::<Expr>(quote!(#receiver.#index));
    }

    let field = format_ident!("{}", atom_or_string(field)?);
    parse_syn::<Expr>(quote!(#receiver.#field))
}

pub(crate) fn parse_index_expr(receiver: Expr, index: Expr) -> NifResult<Expr> {
    parse_syn::<Expr>(quote!(#receiver[#index]))
}

pub(crate) fn parse_range_expr(start: Option<Expr>, stop: Option<Expr>) -> NifResult<Expr> {
    match (start, stop) {
        (Some(start), Some(stop)) => parse_syn::<Expr>(quote!(#start..#stop)),
        (Some(start), None) => parse_syn::<Expr>(quote!(#start..)),
        (None, Some(stop)) => parse_syn::<Expr>(quote!(..#stop)),
        (None, None) => parse_syn::<Expr>(quote!(..)),
    }
}

pub(crate) fn parse_cast_expr(expr: Expr, ty: Type) -> NifResult<Expr> {
    parse_syn::<Expr>(quote!(#expr as #ty))
}

pub(crate) fn parse_unary_expr(op: String, expr: Expr) -> NifResult<Expr> {
    match op.as_str() {
        "not" => parse_syn::<Expr>(quote!( !#expr )),
        "neg" => parse_syn::<Expr>(quote!( -#expr )),
        "deref" => parse_syn::<Expr>(quote!( *#expr )),
        _ => Err(rustler::Error::BadArg),
    }
}

pub(crate) fn parse_byte_string_expr(value: String) -> NifResult<Expr> {
    let bytes = proc_macro2::Literal::byte_string(value.as_bytes());
    parse_syn::<Expr>(quote!(#bytes))
}

pub(crate) fn parse_array_expr(values: Vec<Expr>) -> NifResult<Expr> {
    parse_syn::<Expr>(quote!([#(#values),*]))
}

pub(crate) fn parse_local_call(name: String, args: Vec<Expr>) -> NifResult<Expr> {
    if name.ends_with('!') {
        return Err(rustler::Error::BadArg);
    }

    let name = format_ident!("{}", name);
    parse_syn::<Expr>(quote!(#name(#(#args),*)))
}

pub(crate) struct NamedField<T> {
    name: proc_macro2::Ident,
    value: T,
}

impl<T: ToTokens> ToTokens for NamedField<T> {
    fn to_tokens(&self, tokens: &mut proc_macro2::TokenStream) {
        let name = &self.name;
        let value = &self.value;
        tokens.extend(quote!(#name: #value));
    }
}

pub(crate) fn decode_struct_literal_fields(term: Term) -> NifResult<Vec<NamedField<Expr>>> {
    decode_named_field_list(term, decode_expr)
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

pub(crate) fn parse_path_expr(path: syn::Path) -> NifResult<Expr> {
    parse_syn::<Expr>(quote!(#path))
}

pub(crate) fn parse_atom_value_expr(
    module: Vec<String>,
    name: proc_macro2::Ident,
) -> NifResult<Expr> {
    let module = path_from_parts(module)?;
    parse_syn::<Expr>(quote!(#module::#name()))
}

pub(crate) fn parse_item_use_group_term(term: Term) -> NifResult<syn::ItemUse> {
    let (base, names) = term.decode::<(Term, Term)>()?;
    crate::parse_item_use_group(decode_string_list(base)?, decode_string_list(names)?)
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

enum LiteralTerm {
    Bool(bool),
    I64(i64),
    F64(f64),
    String(String),
    Atom(String),
}

fn decode_literal_term(term: Term) -> NifResult<LiteralTerm> {
    if let Ok(value) = term.decode::<bool>() {
        return Ok(LiteralTerm::Bool(value));
    }
    if let Ok(value) = term.decode::<i64>() {
        return Ok(LiteralTerm::I64(value));
    }
    if let Ok(value) = term.decode::<f64>() {
        return Ok(LiteralTerm::F64(value));
    }
    if let Ok(value) = term.decode::<String>() {
        return Ok(LiteralTerm::String(value));
    }
    if term.is_atom() {
        return Ok(LiteralTerm::Atom(term.atom_to_string()?));
    }
    Err(rustler::Error::BadArg)
}

pub(crate) fn decode_pat_literal_value(term: Term) -> NifResult<Pat> {
    match decode_literal_term(term)? {
        LiteralTerm::String(value) | LiteralTerm::Atom(value) => parse_syn::<Pat>(quote!(#value)),
        _ => Err(rustler::Error::BadArg),
    }
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

pub(crate) fn decode_named_field_list<T>(
    term: Term,
    decoder: fn(Term) -> NifResult<T>,
) -> NifResult<Vec<NamedField<T>>> {
    term.decode::<Vec<(Term, Term)>>()?
        .into_iter()
        .map(|(name, value)| {
            Ok(NamedField {
                name: format_ident!("{}", atom_or_string(name)?),
                value: decoder(value)?,
            })
        })
        .collect()
}

pub(crate) fn decode_pat_struct_fields(term: Term) -> NifResult<Vec<NamedField<Pat>>> {
    decode_named_field_list(term, decode_pat)
}

pub(crate) fn decode_expr_list(term: Term) -> NifResult<Vec<Expr>> {
    decode_list(term, decode_expr)
}

pub(crate) fn decode_optional_path_field(term: Term, field: &str) -> NifResult<Option<syn::Path>> {
    let value = term.map_get(atom(term.get_env(), field)?)?;

    if is_nil(value)? {
        Ok(None)
    } else {
        Ok(Some(parse_ast_path(value)?))
    }
}

pub(crate) fn decode_ident_list(term: Term) -> NifResult<Vec<proc_macro2::Ident>> {
    decode_string_list(term).map(|names| {
        names
            .into_iter()
            .map(|name| format_ident!("{}", name))
            .collect()
    })
}

pub(crate) fn decode_literal_expr(term: Term) -> NifResult<Expr> {
    match decode_literal_term(term)? {
        LiteralTerm::Bool(true) => parse_syn::<Expr>(quote!(true)),
        LiteralTerm::Bool(false) => parse_syn::<Expr>(quote!(false)),
        LiteralTerm::I64(value) => parse_syn::<Expr>(quote!(#value)),
        LiteralTerm::F64(value) => parse_expr(format_float_literal(value)),
        LiteralTerm::String(value) => parse_syn::<Expr>(quote!(#value)),
        LiteralTerm::Atom(_) => Err(rustler::Error::BadArg),
    }
}

fn format_float_literal(value: f64) -> String {
    let formatted = value.to_string();

    if formatted.contains('.') || formatted.contains('e') || formatted.contains('E') {
        formatted
    } else {
        format!("{formatted}.0")
    }
}

pub(crate) fn path_parts(term: Term) -> NifResult<String> {
    crate::generated_ast::path_parts(term)
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

pub(crate) fn decode_string_list(term: Term) -> NifResult<Vec<String>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(atom_or_string)
        .collect::<NifResult<Vec<String>>>()
}
