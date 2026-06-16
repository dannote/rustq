use std::collections::HashMap;

use quote::{format_ident, quote};
use rustler::{Encoder, Env, NifMap, NifResult, Term};
use syn::parse::Parser;
use syn::punctuated::Punctuated;
use syn::token::Comma;
use syn::visit_mut::{self, VisitMut};
use syn::{
    Arm, Expr, ExprMatch, ExprStruct, Field, FieldValue, Fields, File, FnArg, ImplItem, Item,
    Lifetime, Pat, Signature, Stmt, Type,
};

mod generated_ast;

use generated_ast::{atom, atom_key, atoms, is_nil, optional_map_get};
use generated_ast::{decode_arm, decode_enum_variant, decode_struct_field};
use generated_ast::{
    decode_ast_expr, decode_ast_item, decode_ast_pat, decode_ast_stmt, decode_ast_type,
};

#[derive(NifMap)]
struct ErrorInfo {
    r#type: String,
    context: String,
    message: String,
    name: Option<String>,
    fragment: Option<String>,
}

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
        .collect::<Result<syn::punctuated::Punctuated<FnArg, Comma>, syn::Error>>()
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
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_struct_field)
        .collect::<NifResult<Vec<Field>>>()
}

fn decode_enum_variant_list(term: Term) -> NifResult<Vec<syn::Variant>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_enum_variant)
        .collect::<NifResult<Vec<syn::Variant>>>()
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
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_type)
        .collect::<NifResult<Vec<Type>>>()
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
fn decode_stmt_list(term: Term) -> NifResult<Vec<Stmt>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_stmt)
        .collect()
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
        parse_stmt(quote!(let #pat_tokens: #ty = #expr;))
    } else {
        parse_stmt(quote!(let #pat_tokens = #expr;))
    }
}

fn expr_ident(ident: proc_macro2::Ident) -> NifResult<Expr> {
    parse_expr_tokens(quote!(#ident))
}

fn expr_atom_value(name: proc_macro2::Ident) -> NifResult<Expr> {
    parse_expr_tokens(quote!(atoms::#name()))
}

fn expr_field(receiver: Expr, field: proc_macro2::Ident) -> NifResult<Expr> {
    parse_expr_tokens(quote!(#receiver.#field))
}

fn expr_path_call(path: syn::Path, args: Vec<Expr>) -> NifResult<Expr> {
    parse_expr_tokens(quote!(#path(#(#args),*)))
}

fn expr_method_call(
    receiver: Expr,
    method: proc_macro2::Ident,
    args: Vec<Expr>,
) -> NifResult<Expr> {
    parse_expr_tokens(quote!(#receiver.#method(#(#args),*)))
}

fn expr_tuple(values: Vec<Expr>) -> NifResult<Expr> {
    parse_expr_tokens(quote!((#(#values),*)))
}

fn expr_binary(left: Expr, op: &str, right: Expr) -> NifResult<Expr> {
    match op {
        "eq" => parse_expr_tokens(quote!(#left == #right)),
        "and" => parse_expr_tokens(quote!(#left && #right)),
        "or" => parse_expr_tokens(quote!(#left || #right)),
        _ => Err(rustler::Error::BadArg),
    }
}

fn expr_match(expr: Expr, arms: Vec<Arm>) -> NifResult<Expr> {
    parse_expr_tokens(quote!(match #expr { #(#arms)* }))
}

fn expr_if(condition: Expr, then_block: syn::Block, else_block: syn::Block) -> NifResult<Expr> {
    parse_expr_tokens(quote!(if #condition #then_block else #else_block))
}

fn expr_struct_literal(path: Expr, fields: Vec<proc_macro2::TokenStream>) -> NifResult<Expr> {
    parse_expr_tokens(quote!(#path { #(#fields),* }))
}

fn expr_nif_raise_atom(name: String) -> NifResult<Expr> {
    parse_expr_tokens(quote!(rustler::Error::RaiseAtom(#name)))
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
        parse_expr_tokens(quote!(#name(#(#args),*)))
    }
}

fn decode_struct_literal_fields(term: Term) -> NifResult<Vec<proc_macro2::TokenStream>> {
    term.decode::<Vec<(Term, Term)>>()?
        .into_iter()
        .map(|(name, expr)| {
            let name = format_ident!("{}", atom_or_string(name)?);
            let expr = decode_expr(expr)?;
            Ok(quote!(#name: #expr))
        })
        .collect()
}

fn decode_arm_list(term: Term) -> NifResult<Vec<Arm>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_arm)
        .collect()
}

fn parse_arm(tokens: proc_macro2::TokenStream) -> NifResult<Arm> {
    syn::parse2(tokens).map_err(|_| rustler::Error::BadArg)
}

fn decode_atom_guard_arm(pat_term: Term, block: syn::Block) -> NifResult<Arm> {
    let name = format_ident!("{}", atom_key(pat_term, "name")?);
    parse_arm(quote!(value if value == atoms::#name() => #block,))
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

fn decode_optional_type_field(term: Term, key: &str) -> NifResult<Option<Type>> {
    match optional_map_get(term, key)? {
        Some(type_term) if !is_nil(type_term)? => Ok(Some(decode_type(type_term)?)),
        _ => Ok(None),
    }
}

fn decode_optional_expr_field(term: Term, key: &str) -> NifResult<Option<Expr>> {
    match optional_map_get(term, key)? {
        Some(expr_term) if !is_nil(expr_term)? => Ok(Some(decode_expr(expr_term)?)),
        _ => Ok(None),
    }
}

fn decode_pat_literal_value(term: Term) -> NifResult<Pat> {
    if let Ok(value) = term.decode::<String>() {
        return parse_pat(quote!(#value));
    }
    if term.is_atom() {
        let value = term.atom_to_string()?;
        return parse_pat(quote!(#value));
    }
    Err(rustler::Error::BadArg)
}

fn parse_pat(tokens: proc_macro2::TokenStream) -> NifResult<Pat> {
    Pat::parse_single
        .parse2(tokens)
        .map_err(|_| rustler::Error::BadArg)
}

fn parse_stmt(tokens: proc_macro2::TokenStream) -> NifResult<Stmt> {
    syn::parse2(tokens).map_err(|_| rustler::Error::BadArg)
}

fn decode_pat(term: Term) -> NifResult<Pat> {
    decode_ast_pat(term)
}

fn decode_pat_atom_guard(_term: Term) -> NifResult<Pat> {
    Err(rustler::Error::BadArg)
}

fn decode_pat_list(term: Term) -> NifResult<Vec<Pat>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_pat)
        .collect()
}

fn pat_ident(ident: proc_macro2::Ident) -> NifResult<Pat> {
    parse_pat(quote!(#ident))
}

fn pat_path(path: syn::Path) -> NifResult<Pat> {
    parse_pat(quote!(#path))
}

fn pat_tuple(patterns: Vec<Pat>) -> NifResult<Pat> {
    parse_pat(quote!((#(#patterns),*)))
}

fn pat_path_tuple(path: syn::Path, patterns: Vec<Pat>) -> NifResult<Pat> {
    parse_pat(quote!(#path(#(#patterns),*)))
}

fn pat_struct(path: syn::Path, fields: Vec<proc_macro2::TokenStream>) -> NifResult<Pat> {
    parse_pat(quote!(#path { #(#fields),* }))
}

fn arm_match(pat: Pat, block: syn::Block) -> NifResult<Arm> {
    parse_arm(quote!(#pat => #block,))
}

fn decode_pat_struct_fields(term: Term) -> NifResult<Vec<proc_macro2::TokenStream>> {
    term.decode::<Vec<(Term, Term)>>()?
        .into_iter()
        .map(|(name, pattern)| {
            let name = format_ident!("{}", atom_or_string(name)?);
            let pattern = decode_pat(pattern)?;
            Ok(quote!(#name: #pattern))
        })
        .collect()
}

fn decode_expr_list(term: Term) -> NifResult<Vec<Expr>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_expr)
        .collect()
}

fn decode_literal_expr(term: Term) -> NifResult<Expr> {
    if let Ok(value) = term.decode::<bool>() {
        return if value {
            Ok(syn::parse2(quote!(true)).map_err(|_| rustler::Error::BadArg)?)
        } else {
            Ok(syn::parse2(quote!(false)).map_err(|_| rustler::Error::BadArg)?)
        };
    }
    if let Ok(value) = term.decode::<i64>() {
        return Ok(syn::parse2(quote!(#value)).map_err(|_| rustler::Error::BadArg)?);
    }
    if let Ok(value) = term.decode::<f64>() {
        return Ok(syn::parse2(quote!(#value)).map_err(|_| rustler::Error::BadArg)?);
    }
    if let Ok(value) = term.decode::<String>() {
        return Ok(syn::parse2(quote!(#value)).map_err(|_| rustler::Error::BadArg)?);
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

fn parse_type(source: &str) -> NifResult<Type> {
    syn::parse_str(source).map_err(|_| rustler::Error::BadArg)
}

fn parse_path(source: &str) -> NifResult<syn::Path> {
    syn::parse_str(source).map_err(|_| rustler::Error::BadArg)
}

fn parse_expr(source: &str) -> NifResult<Expr> {
    syn::parse_str(source).map_err(|_| rustler::Error::BadArg)
}

fn parse_expr_tokens(tokens: proc_macro2::TokenStream) -> NifResult<Expr> {
    syn::parse2(tokens).map_err(|_| rustler::Error::BadArg)
}

struct Context {
    bindings: HashMap<String, String>,
    splices: HashMap<String, Vec<String>>,
}

fn template_error(error: syn::Error) -> ErrorInfo {
    ErrorInfo {
        r#type: "invalid_template".to_string(),
        context: "template".to_string(),
        message: error.to_string(),
        name: None,
        fragment: None,
    }
}

fn splice_error(context: &str, name: &str, fragment: &str, error: syn::Error) -> ErrorInfo {
    ErrorInfo {
        r#type: "invalid_splice".to_string(),
        context: context.to_string(),
        message: error.to_string(),
        name: Some(name.to_string()),
        fragment: Some(fragment.to_string()),
    }
}

fn binding_error(context: &str, name: &str, value: &str, error: syn::Error) -> ErrorInfo {
    ErrorInfo {
        r#type: "invalid_binding".to_string(),
        context: context.to_string(),
        message: error.to_string(),
        name: Some(name.to_string()),
        fragment: Some(value.to_string()),
    }
}

fn render_source(
    source: &str,
    bindings: Vec<(String, String)>,
    splices: Vec<(String, Vec<String>)>,
) -> Result<String, Vec<ErrorInfo>> {
    let mut file = syn::parse_file(source).map_err(|error| vec![template_error(error)])?;
    let context = Context {
        bindings: bindings.into_iter().collect(),
        splices: splices.into_iter().collect(),
    };

    splice_file(&mut file, &context)?;

    let mut binder = Binder::new(&context.bindings);
    binder.visit_file_mut(&mut file);
    binder.finish()?;

    Ok(prettyplease::unparse(&file))
}

fn splice_file(file: &mut File, context: &Context) -> Result<(), Vec<ErrorInfo>> {
    splice_items(&mut file.items, context)
}

fn splice_items(items: &mut Vec<Item>, context: &Context) -> Result<(), Vec<ErrorInfo>> {
    let mut next = Vec::new();

    for mut item in std::mem::take(items) {
        if let Some(name) = item_splice_name(&item) {
            next.extend(parse_items(&name, context)?);
        } else {
            splice_item(&mut item, context)?;
            next.push(item);
        }
    }

    *items = next;
    Ok(())
}

fn splice_item(item: &mut Item, context: &Context) -> Result<(), Vec<ErrorInfo>> {
    match item {
        Item::Impl(item_impl) => splice_impl_items(&mut item_impl.items, context),
        Item::Mod(item_mod) => {
            if let Some((_, items)) = &mut item_mod.content {
                splice_items(items, context)?;
            }
            Ok(())
        }
        Item::Struct(item_struct) => splice_fields(&mut item_struct.fields, context),
        Item::Fn(item_fn) => {
            splice_signature_inputs(&mut item_fn.sig, context)?;
            splice_stmts(&mut item_fn.block.stmts, context)
        }
        _ => Ok(()),
    }
}

fn splice_impl_items(items: &mut Vec<ImplItem>, context: &Context) -> Result<(), Vec<ErrorInfo>> {
    let mut next = Vec::new();

    for mut item in std::mem::take(items) {
        if let Some(name) = impl_item_splice_name(&item) {
            next.extend(parse_impl_items(&name, context)?);
        } else {
            if let ImplItem::Fn(item_fn) = &mut item {
                splice_signature_inputs(&mut item_fn.sig, context)?;
                splice_stmts(&mut item_fn.block.stmts, context)?;
            }
            next.push(item);
        }
    }

    *items = next;
    Ok(())
}

fn splice_signature_inputs(
    signature: &mut Signature,
    context: &Context,
) -> Result<(), Vec<ErrorInfo>> {
    let mut next = Punctuated::<FnArg, Comma>::new();

    for input in std::mem::take(&mut signature.inputs) {
        if let Some(name) = arg_splice_name(&input) {
            for parsed in parse_args(&name, context)? {
                next.push(parsed);
            }
        } else {
            next.push(input);
        }
    }

    signature.inputs = next;
    Ok(())
}

fn splice_fields(fields: &mut Fields, context: &Context) -> Result<(), Vec<ErrorInfo>> {
    let Fields::Named(fields_named) = fields else {
        return Ok(());
    };

    let mut next = Punctuated::<Field, Comma>::new();

    for field in std::mem::take(&mut fields_named.named) {
        if let Some(name) = field_splice_name(&field) {
            for parsed in parse_fields(&name, context)? {
                next.push(parsed);
            }
        } else {
            next.push(field);
        }
    }

    fields_named.named = next;
    Ok(())
}

fn splice_stmts(stmts: &mut Vec<Stmt>, context: &Context) -> Result<(), Vec<ErrorInfo>> {
    let mut next = Vec::new();

    for stmt in std::mem::take(stmts) {
        if let Some(name) = stmt_splice_name(&stmt) {
            next.extend(parse_stmts(&name, context)?);
        } else {
            let mut stmt = stmt;
            let mut splicer = Splicer::new(context);
            splicer.visit_stmt_mut(&mut stmt);
            splicer.finish()?;
            next.push(stmt);
        }
    }

    *stmts = next;
    Ok(())
}

fn item_splice_name(item: &Item) -> Option<String> {
    let Item::Macro(item_macro) = item else {
        return None;
    };
    splice_name(&item_macro.mac.path)
}

fn impl_item_splice_name(item: &ImplItem) -> Option<String> {
    let ImplItem::Macro(item_macro) = item else {
        return None;
    };
    splice_name(&item_macro.mac.path)
}

fn arg_splice_name(arg: &FnArg) -> Option<String> {
    let FnArg::Typed(pat_type) = arg else {
        return None;
    };

    let Pat::Ident(pat_ident) = pat_type.pat.as_ref() else {
        return None;
    };

    pat_ident
        .ident
        .to_string()
        .strip_prefix("__rq_")
        .map(str::to_string)
}

fn stmt_splice_name(stmt: &Stmt) -> Option<String> {
    let Stmt::Macro(stmt_macro) = stmt else {
        return None;
    };
    splice_name(&stmt_macro.mac.path)
}

fn field_splice_name(field: &Field) -> Option<String> {
    let ident = field.ident.as_ref()?;
    ident.to_string().strip_prefix("__rq_").map(str::to_string)
}

fn splice_name(path: &syn::Path) -> Option<String> {
    let ident = path.get_ident()?;
    ident.to_string().strip_prefix("__rq_").map(str::to_string)
}

fn parse_items(name: &str, context: &Context) -> Result<Vec<Item>, Vec<ErrorInfo>> {
    parse_many_fragments("item", name, context, |source| {
        Ok(syn::parse_str::<syn::File>(source)?.items)
    })
}

fn parse_impl_items(name: &str, context: &Context) -> Result<Vec<ImplItem>, Vec<ErrorInfo>> {
    parse_many_fragments("impl_item", name, context, |source| {
        let wrapped = format!("impl __RustQ {{ {source} }}");
        let item = syn::parse_str::<syn::ItemImpl>(&wrapped)?;
        Ok(item.items)
    })
}

fn parse_fields(name: &str, context: &Context) -> Result<Vec<Field>, Vec<ErrorInfo>> {
    parse_fragments("field", name, context, parse_field)
}

fn parse_args(name: &str, context: &Context) -> Result<Vec<FnArg>, Vec<ErrorInfo>> {
    parse_fragments("arg", name, context, syn::parse_str::<FnArg>)
}

fn parse_field_values(name: &str, context: &Context) -> Result<Vec<FieldValue>, Vec<ErrorInfo>> {
    parse_fragments("field_value", name, context, parse_field_value)
}

fn parse_stmts(name: &str, context: &Context) -> Result<Vec<Stmt>, Vec<ErrorInfo>> {
    parse_fragments("stmt", name, context, syn::parse_str::<Stmt>)
}

fn parse_arms(name: &str, context: &Context) -> Result<Vec<Arm>, Vec<ErrorInfo>> {
    parse_fragments("arm", name, context, syn::parse_str::<Arm>)
}

fn parse_field(source: &str) -> syn::Result<Field> {
    let wrapped = format!("struct __RustQ {{ {source} }}");
    let item = syn::parse_str::<syn::ItemStruct>(&wrapped)?;
    item.fields
        .into_iter()
        .next()
        .ok_or_else(|| syn::Error::new(proc_macro2::Span::call_site(), "expected field"))
}

fn parse_field_value(source: &str) -> syn::Result<FieldValue> {
    let wrapped = format!("__RustQ {{ {source} }}");
    let expr = syn::parse_str::<ExprStruct>(&wrapped)?;
    expr.fields
        .into_iter()
        .next()
        .ok_or_else(|| syn::Error::new(proc_macro2::Span::call_site(), "expected field value"))
}

fn parse_fragments<T, F>(
    fragment_context: &str,
    name: &str,
    context: &Context,
    mut parse: F,
) -> Result<Vec<T>, Vec<ErrorInfo>>
where
    F: FnMut(&str) -> syn::Result<T>,
{
    parse_many_fragments(fragment_context, name, context, |source| {
        parse(source).map(|value| vec![value])
    })
}

fn parse_many_fragments<T, F>(
    fragment_context: &str,
    name: &str,
    context: &Context,
    mut parse: F,
) -> Result<Vec<T>, Vec<ErrorInfo>>
where
    F: FnMut(&str) -> syn::Result<Vec<T>>,
{
    let Some(fragments) = context.splices.get(name) else {
        return Ok(Vec::new());
    };

    let mut parsed = Vec::new();
    let mut errors = Vec::new();

    for fragment in fragments {
        match parse(fragment) {
            Ok(values) => parsed.extend(values),
            Err(error) => errors.push(splice_error(fragment_context, name, fragment, error)),
        }
    }

    if errors.is_empty() {
        Ok(parsed)
    } else {
        Err(errors)
    }
}

struct Splicer<'a> {
    context: &'a Context,
    errors: Vec<ErrorInfo>,
}

impl<'a> Splicer<'a> {
    fn new(context: &'a Context) -> Self {
        Self {
            context,
            errors: Vec::new(),
        }
    }

    fn finish(self) -> Result<(), Vec<ErrorInfo>> {
        if self.errors.is_empty() {
            Ok(())
        } else {
            Err(self.errors)
        }
    }
}

impl VisitMut for Splicer<'_> {
    fn visit_expr_struct_mut(&mut self, expr_struct: &mut ExprStruct) {
        let mut next = Punctuated::<FieldValue, Comma>::new();

        for mut field in std::mem::take(&mut expr_struct.fields) {
            if let Some(name) = field_value_splice_name(&field) {
                match parse_field_values(&name, self.context) {
                    Ok(fields) => {
                        for field in fields {
                            next.push(field);
                        }
                    }
                    Err(errors) => self.errors.extend(errors),
                }
            } else {
                visit_mut::visit_field_value_mut(self, &mut field);
                next.push(field);
            }
        }

        expr_struct.fields = next;
    }

    fn visit_expr_match_mut(&mut self, expr_match: &mut ExprMatch) {
        let mut next = Vec::new();

        for mut arm in std::mem::take(&mut expr_match.arms) {
            if let Some(name) = arm_splice_name(&arm) {
                match parse_arms(&name, self.context) {
                    Ok(arms) => next.extend(arms),
                    Err(errors) => self.errors.extend(errors),
                }
            } else {
                visit_mut::visit_arm_mut(self, &mut arm);
                next.push(arm);
            }
        }

        expr_match.arms = next;
        visit_mut::visit_expr_mut(self, &mut expr_match.expr);
    }
}

fn field_value_splice_name(field: &FieldValue) -> Option<String> {
    let syn::Member::Named(ident) = &field.member else {
        return None;
    };

    ident.to_string().strip_prefix("__rq_").map(str::to_string)
}

fn arm_splice_name(arm: &Arm) -> Option<String> {
    let Pat::Ident(pat_ident) = &arm.pat else {
        return None;
    };

    pat_ident
        .ident
        .to_string()
        .strip_prefix("__rq_")
        .map(str::to_string)
}

struct Binder<'a> {
    bindings: &'a HashMap<String, String>,
    errors: Vec<ErrorInfo>,
}

impl<'a> Binder<'a> {
    fn new(bindings: &'a HashMap<String, String>) -> Self {
        Self {
            bindings,
            errors: Vec::new(),
        }
    }

    fn finish(self) -> Result<(), Vec<ErrorInfo>> {
        if self.errors.is_empty() {
            Ok(())
        } else {
            Err(self.errors)
        }
    }

    fn binding_for_ident(&self, ident: &syn::Ident, prefix: &str) -> Option<&'a str> {
        ident
            .to_string()
            .strip_prefix(prefix)
            .and_then(|name| self.bindings.get(name))
            .map(String::as_str)
    }

    fn binding_for_macro_path(&self, path: &syn::Path, prefix: &str) -> Option<(String, &'a str)> {
        let ident = path.get_ident()?;
        let ident = ident.to_string();
        let name = ident.strip_prefix(prefix)?.to_string();
        let value = self.bindings.get(&name)?;
        Some((name, value.as_str()))
    }
}

impl VisitMut for Binder<'_> {
    fn visit_ident_mut(&mut self, ident: &mut syn::Ident) {
        if let Some(value) = self.binding_for_ident(ident, "__rq_") {
            match syn::parse_str::<syn::Ident>(value) {
                Ok(parsed) => *ident = parsed,
                Err(error) => self.errors.push(binding_error(
                    "ident_binding",
                    &ident.to_string(),
                    value,
                    error,
                )),
            }
        }
    }

    fn visit_lifetime_mut(&mut self, lifetime: &mut Lifetime) {
        let name = lifetime.ident.to_string();

        if let Some(value) = name
            .strip_prefix("__rq_")
            .and_then(|name| self.bindings.get(name))
        {
            let value = value.trim_start_matches('\'');
            *lifetime = Lifetime::new(&format!("'{value}"), lifetime.apostrophe);
        }
    }

    fn visit_expr_mut(&mut self, expr: &mut Expr) {
        if let Expr::Macro(expr_macro) = expr {
            if let Some((name, value)) = self.binding_for_macro_path(&expr_macro.mac.path, "__rq_")
            {
                match syn::parse_str::<Expr>(value) {
                    Ok(parsed) => *expr = parsed,
                    Err(error) => {
                        self.errors
                            .push(binding_error("expr_binding", &name, value, error))
                    }
                }
                return;
            }
        }

        visit_mut::visit_expr_mut(self, expr);
    }

    fn visit_type_mut(&mut self, ty: &mut Type) {
        if let Type::Macro(type_macro) = ty {
            if let Some((name, value)) = self.binding_for_macro_path(&type_macro.mac.path, "__rq_")
            {
                match syn::parse_str::<Type>(value) {
                    Ok(parsed) => *ty = parsed,
                    Err(error) => {
                        self.errors
                            .push(binding_error("type_binding", &name, value, error))
                    }
                }
                return;
            }
        }

        visit_mut::visit_type_mut(self, ty);
    }

    fn visit_arm_mut(&mut self, arm: &mut Arm) {
        visit_mut::visit_arm_mut(self, arm);
    }
}

rustler::init!("Elixir.RustQ.Native");
