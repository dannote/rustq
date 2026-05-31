use std::collections::HashMap;

use rustler::{Encoder, Env, NifMap, NifResult, Term};
use syn::punctuated::Punctuated;
use syn::token::Comma;
use syn::visit_mut::{self, VisitMut};
use syn::{Arm, Expr, ExprMatch, Field, Fields, File, ImplItem, Item, Pat, Stmt, Type};

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
        Item::Fn(item_fn) => splice_stmts(&mut item_fn.block.stmts, context),
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
                splice_stmts(&mut item_fn.block.stmts, context)?;
            }
            next.push(item);
        }
    }

    *items = next;
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

fn stmt_splice_name(stmt: &Stmt) -> Option<String> {
    let Stmt::Macro(stmt_macro) = stmt else {
        return None;
    };
    splice_name(&stmt_macro.mac.path)
}

fn field_splice_name(field: &Field) -> Option<String> {
    let ident = field.ident.as_ref()?;
    ident
        .to_string()
        .strip_prefix("__splice_")
        .map(str::to_string)
}

fn splice_name(path: &syn::Path) -> Option<String> {
    let ident = path.get_ident()?;
    ident
        .to_string()
        .strip_prefix("__splice_")
        .map(str::to_string)
}

fn parse_items(name: &str, context: &Context) -> Result<Vec<Item>, Vec<ErrorInfo>> {
    parse_fragments("item", name, context, syn::parse_str::<Item>)
}

fn parse_impl_items(name: &str, context: &Context) -> Result<Vec<ImplItem>, Vec<ErrorInfo>> {
    parse_fragments("impl_item", name, context, syn::parse_str::<ImplItem>)
}

fn parse_fields(name: &str, context: &Context) -> Result<Vec<Field>, Vec<ErrorInfo>> {
    parse_fragments("field", name, context, parse_field)
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

fn parse_fragments<T, F>(
    fragment_context: &str,
    name: &str,
    context: &Context,
    mut parse: F,
) -> Result<Vec<T>, Vec<ErrorInfo>>
where
    F: FnMut(&str) -> syn::Result<T>,
{
    let Some(fragments) = context.splices.get(name) else {
        return Ok(Vec::new());
    };

    let mut parsed = Vec::new();
    let mut errors = Vec::new();

    for fragment in fragments {
        match parse(fragment) {
            Ok(value) => parsed.push(value),
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

fn arm_splice_name(arm: &Arm) -> Option<String> {
    let Pat::Ident(pat_ident) = &arm.pat else {
        return None;
    };

    pat_ident
        .ident
        .to_string()
        .strip_prefix("__splice_")
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
        if let Some(value) = self.binding_for_ident(ident, "__") {
            *ident = syn::Ident::new(value, ident.span());
        }
    }

    fn visit_expr_mut(&mut self, expr: &mut Expr) {
        if let Expr::Macro(expr_macro) = expr {
            if let Some((name, value)) =
                self.binding_for_macro_path(&expr_macro.mac.path, "__expr_")
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
            if let Some((name, value)) =
                self.binding_for_macro_path(&type_macro.mac.path, "__type_")
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
