use rustler::NifResult;
use syn::parse::Parser;
use syn::{Arm, Block, Expr, Pat, Stmt, Type};

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
    syn::FnArg,
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
