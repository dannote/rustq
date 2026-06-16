use std::collections::HashMap;

use quote::{format_ident, quote};
use rustler::{Atom, Encoder, Env, NifMap, NifResult, Term};
use syn::parse::Parser;
use syn::punctuated::Punctuated;
use syn::token::Comma;
use syn::visit_mut::{self, VisitMut};
use syn::{
    Arm, Expr, ExprMatch, ExprStruct, Field, FieldValue, Fields, File, FnArg, ImplItem, Item,
    Lifetime, Pat, Signature, Stmt, Type,
};

mod atoms {
    rustler::atoms! {
        ok,
        error,
    }
}

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

fn decode_ast_item(term: Term) -> NifResult<Item> {
    match struct_name(term)?.as_str() {
        "Elixir.RustQ.Rust.AST.Function" => Ok(Item::Fn(decode_ast_function(term)?)),
        "Elixir.RustQ.Rust.AST.Struct" => Ok(Item::Struct(decode_ast_struct(term)?)),
        "Elixir.RustQ.Rust.AST.Enum" => Ok(Item::Enum(decode_ast_enum(term)?)),
        _ => Err(rustler::Error::BadArg),
    }
}

fn decode_ast_function(term: Term) -> NifResult<syn::ItemFn> {
    expect_struct(term, "Elixir.RustQ.Rust.AST.Function")?;
    let env = term.get_env();
    let name = format_ident!("{}", atom_key(term, "name")?);
    let args = keyword_args(term.map_get(atom(env, "args")?)?)?;
    let returns = type_value(term, "returns")?;
    let lifetime = optional_atom_key(term, "lifetime")?;
    let stmts = decode_stmt_list(term.map_get(atom(env, "body")?)?)?;
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
        syn::parse2(quote!(fn #name <#lifetime> (#inputs) -> #returns #block))
            .map_err(|_| rustler::Error::BadArg)
    } else {
        syn::parse2(quote!(fn #name (#inputs) -> #returns #block))
            .map_err(|_| rustler::Error::BadArg)
    }
}

fn decode_ast_struct(term: Term) -> NifResult<syn::ItemStruct> {
    expect_struct(term, "Elixir.RustQ.Rust.AST.Struct")?;
    let env = term.get_env();
    let name = format_ident!("{}", atom_key(term, "name")?);
    let vis = decode_vis(term.map_get(atom(env, "vis")?)?)?;
    let derive = decode_derive(term.map_get(atom(env, "derive")?)?)?;
    let lifetime = optional_atom_key(term, "lifetime")?;
    let fields = term
        .map_get(atom(env, "fields")?)?
        .decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_struct_field)
        .collect::<NifResult<Vec<Field>>>()?;

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

fn decode_struct_field(term: Term) -> NifResult<Field> {
    expect_struct(term, "Elixir.RustQ.Rust.AST.StructField")?;
    let env = term.get_env();
    let name = format_ident!("{}", atom_key(term, "name")?);
    let ty: String = term.map_get(atom(env, "type")?)?.decode()?;
    let ty = parse_type(&ty)?;
    let vis = decode_vis(term.map_get(atom(env, "vis")?)?)?;
    let item: syn::ItemStruct = syn::parse2(quote!(struct __RustQ { #vis #name: #ty, }))
        .map_err(|_| rustler::Error::BadArg)?;
    item.fields.into_iter().next().ok_or(rustler::Error::BadArg)
}

fn decode_ast_enum(term: Term) -> NifResult<syn::ItemEnum> {
    expect_struct(term, "Elixir.RustQ.Rust.AST.Enum")?;
    let env = term.get_env();
    let name = format_ident!("{}", atom_key(term, "name")?);
    let vis = decode_vis(term.map_get(atom(env, "vis")?)?)?;
    let derive = decode_derive(term.map_get(atom(env, "derive")?)?)?;
    let variants = term
        .map_get(atom(env, "variants")?)?
        .decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_enum_variant)
        .collect::<NifResult<Vec<syn::Variant>>>()?;

    syn::parse2(quote!(#(#derive)* #vis enum #name { #(#variants)* }))
        .map_err(|_| rustler::Error::BadArg)
}

fn decode_enum_variant(term: Term) -> NifResult<syn::Variant> {
    expect_struct(term, "Elixir.RustQ.Rust.AST.EnumVariant")?;
    let name = format_ident!("{}", atom_key(term, "name")?);
    syn::parse2(quote!(#name,)).map_err(|_| rustler::Error::BadArg)
}

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

fn decode_stmt_list(term: Term) -> NifResult<Vec<Stmt>> {
    term.decode::<Vec<Term>>()?
        .into_iter()
        .map(decode_stmt)
        .collect()
}

fn decode_stmt(term: Term) -> NifResult<Stmt> {
    let module = struct_name(term)?;

    match module.as_str() {
        "Elixir.RustQ.Rust.AST.Let" => {
            let env = term.get_env();
            let pat = decode_pat(term.map_get(atom(env, "pattern")?)?)?;
            let expr = decode_expr(term.map_get(atom(env, "expr")?)?)?;
            let mutable = term.map_get(atom(env, "mutable")?)?.decode::<bool>()?;

            if mutable {
                let Pat::Ident(mut pat_ident) = pat else {
                    return Err(rustler::Error::BadArg);
                };
                pat_ident.mutability = Some(Default::default());
                Ok(syn::parse2(quote!(let #pat_ident = #expr;))
                    .map_err(|_| rustler::Error::BadArg)?)
            } else {
                Ok(syn::parse2(quote!(let #pat = #expr;)).map_err(|_| rustler::Error::BadArg)?)
            }
        }
        "Elixir.RustQ.Rust.AST.ExprStmt" => {
            let expr = decode_expr(term.map_get(atom(term.get_env(), "expr")?)?)?;
            Ok(syn::parse2(quote!(#expr;)).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Return" => {
            let expr = decode_expr(term.map_get(atom(term.get_env(), "expr")?)?)?;
            Ok(Stmt::Expr(expr, None))
        }
        _ => Err(rustler::Error::BadArg),
    }
}

fn decode_expr(term: Term) -> NifResult<Expr> {
    let module = struct_name(term)?;
    let env = term.get_env();

    match module.as_str() {
        "Elixir.RustQ.Rust.AST.Var" => {
            let ident = format_ident!("{}", atom_key(term, "name")?);
            Ok(syn::parse2(quote!(#ident)).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Path" => {
            parse_expr(&path_parts(term.map_get(atom(env, "parts")?)?)?)
        }
        "Elixir.RustQ.Rust.AST.Field" => {
            let receiver = decode_expr(term.map_get(atom(env, "receiver")?)?)?;
            let field = format_ident!("{}", atom_key(term, "field")?);
            Ok(syn::parse2(quote!(#receiver.#field)).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.PathCall" => {
            let path = parse_path(&path_parts(
                term.map_get(atom(env, "path")?)?
                    .map_get(atom(env, "parts")?)?,
            )?)?;
            let args = decode_expr_list(term.map_get(atom(env, "args")?)?)?;
            Ok(syn::parse2(quote!(#path(#(#args),*))).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.MethodCall" => {
            let receiver = decode_expr(term.map_get(atom(env, "receiver")?)?)?;
            let method = format_ident!("{}", atom_key(term, "method")?);
            let args = decode_expr_list(term.map_get(atom(env, "args")?)?)?;
            Ok(syn::parse2(quote!(#receiver.#method(#(#args),*)))
                .map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.LocalCall" => {
            let name = format_ident!("{}", atom_key(term, "name")?);
            let args = decode_expr_list(term.map_get(atom(env, "args")?)?)?;
            Ok(syn::parse2(quote!(#name(#(#args),*))).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Ref" => {
            let expr = decode_expr(term.map_get(atom(env, "expr")?)?)?;
            if term.map_get(atom(env, "mutable")?)?.decode::<bool>()? {
                Ok(syn::parse2(quote!(&mut #expr)).map_err(|_| rustler::Error::BadArg)?)
            } else {
                Ok(syn::parse2(quote!(&#expr)).map_err(|_| rustler::Error::BadArg)?)
            }
        }
        "Elixir.RustQ.Rust.AST.Try" => {
            let expr = decode_expr(term.map_get(atom(env, "expr")?)?)?;
            Ok(syn::parse2(quote!(#expr?)).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Tuple" => {
            let values = decode_expr_list(term.map_get(atom(env, "values")?)?)?;
            Ok(syn::parse2(quote!((#(#values),*))).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Literal" => decode_literal_expr(term.map_get(atom(env, "value")?)?),
        "Elixir.RustQ.Rust.AST.AtomValue" => {
            let name = format_ident!("{}", atom_key(term, "name")?);
            Ok(syn::parse2(quote!(atoms::#name())).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.None" => {
            Ok(syn::parse2(quote!(None)).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Some" => {
            let expr = decode_expr(term.map_get(atom(env, "expr")?)?)?;
            Ok(syn::parse2(quote!(Some(#expr))).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Ok" => match optional_map_get(term, "expr")? {
            Some(expr_term) if !is_nil(expr_term)? => {
                let expr = decode_expr(expr_term)?;
                Ok(syn::parse2(quote!(Ok(#expr))).map_err(|_| rustler::Error::BadArg)?)
            }
            _ => Ok(syn::parse2(quote!(Ok(()))).map_err(|_| rustler::Error::BadArg)?),
        },
        "Elixir.RustQ.Rust.AST.Err" => {
            let expr = decode_expr(term.map_get(atom(env, "expr")?)?)?;
            Ok(syn::parse2(quote!(Err(#expr))).map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.NifRaiseAtom" => {
            let name = atom_key(term, "name")?;
            Ok(syn::parse2(quote!(rustler::Error::RaiseAtom(#name)))
                .map_err(|_| rustler::Error::BadArg)?)
        }
        "Elixir.RustQ.Rust.AST.Match" => {
            let expr = decode_expr(term.map_get(atom(env, "expr")?)?)?;
            let arms = term
                .map_get(atom(env, "arms")?)?
                .decode::<Vec<Term>>()?
                .into_iter()
                .map(decode_arm)
                .collect::<NifResult<Vec<Arm>>>()?;
            Ok(syn::parse2(quote!(match #expr { #(#arms)* }))
                .map_err(|_| rustler::Error::BadArg)?)
        }
        _ => Err(rustler::Error::BadArg),
    }
}

fn decode_arm(term: Term) -> NifResult<Arm> {
    expect_struct(term, "Elixir.RustQ.Rust.AST.Arm")?;
    let env = term.get_env();
    let pat_term = term.map_get(atom(env, "pattern")?)?;
    let body = decode_stmt_list(term.map_get(atom(env, "body")?)?)?;
    let block =
        syn::parse2::<syn::Block>(quote!({ #(#body)* })).map_err(|_| rustler::Error::BadArg)?;

    match struct_name(pat_term)?.as_str() {
        "Elixir.RustQ.Rust.AST.PatAtomGuard" => {
            let name = format_ident!("{}", atom_key(pat_term, "name")?);
            syn::parse2(quote!(value if value == atoms::#name() => #block,))
                .map_err(|_| rustler::Error::BadArg)
        }
        _ => {
            let pat = decode_pat(pat_term)?;
            syn::parse2(quote!(#pat => #block,)).map_err(|_| rustler::Error::BadArg)
        }
    }
}

fn parse_pat(tokens: proc_macro2::TokenStream) -> NifResult<Pat> {
    Pat::parse_single
        .parse2(tokens)
        .map_err(|_| rustler::Error::BadArg)
}

fn decode_pat(term: Term) -> NifResult<Pat> {
    let module = struct_name(term)?;
    let env = term.get_env();

    match module.as_str() {
        "Elixir.RustQ.Rust.AST.PatVar" => {
            let ident = format_ident!("{}", atom_key(term, "name")?);
            parse_pat(quote!(#ident))
        }
        "Elixir.RustQ.Rust.AST.PatWildcard" => parse_pat(quote!(_)),
        "Elixir.RustQ.Rust.AST.PatNone" => parse_pat(quote!(None)),
        "Elixir.RustQ.Rust.AST.PatSome" => {
            let pat = decode_pat(term.map_get(atom(env, "pattern")?)?)?;
            parse_pat(quote!(Some(#pat)))
        }
        "Elixir.RustQ.Rust.AST.PatTuple" => {
            let patterns = term
                .map_get(atom(env, "patterns")?)?
                .decode::<Vec<Term>>()?
                .into_iter()
                .map(decode_pat)
                .collect::<NifResult<Vec<Pat>>>()?;
            parse_pat(quote!((#(#patterns),*)))
        }
        _ => Err(rustler::Error::BadArg),
    }
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
    term.decode::<Vec<(Term, String)>>()?
        .into_iter()
        .map(|(name, ty)| Ok((atom_or_string(name)?, parse_type(&ty)?)))
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

fn type_value(term: Term, key: &str) -> NifResult<Type> {
    let source: String = term.map_get(atom(term.get_env(), key)?)?.decode()?;
    parse_type(&source)
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

fn atom(env: Env, name: &str) -> NifResult<Atom> {
    Atom::from_str(env, name)
}

fn optional_map_get<'a>(term: Term<'a>, key: &str) -> NifResult<Option<Term<'a>>> {
    match term.map_get(atom(term.get_env(), key)?) {
        Ok(value) => Ok(Some(value)),
        Err(_) => Ok(None),
    }
}

fn atom_key(term: Term, key: &str) -> NifResult<String> {
    term.map_get(atom(term.get_env(), key)?)?.atom_to_string()
}

fn optional_atom_key(term: Term, key: &str) -> NifResult<Option<String>> {
    let value = term.map_get(atom(term.get_env(), key)?)?;
    if is_nil(value)? {
        Ok(None)
    } else {
        Ok(Some(value.atom_to_string()?))
    }
}

fn is_nil(term: Term) -> NifResult<bool> {
    Ok(term.is_atom() && term.atom_to_string()? == "nil")
}

fn struct_name(term: Term) -> NifResult<String> {
    term.map_get(atom(term.get_env(), "__struct__")?)?
        .atom_to_string()
}

fn expect_struct(term: Term, expected: &str) -> NifResult<()> {
    if struct_name(term)? == expected {
        Ok(())
    } else {
        Err(rustler::Error::BadArg)
    }
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
