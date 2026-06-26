#![allow(dead_code)]
#![allow(non_snake_case)]
#![allow(clippy::manual_ok_err)]
#![allow(clippy::manual_unwrap_or_default)]

use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc, Term};
use std::sync::OnceLock;

struct Node;

#[allow(dead_code)]
pub enum NodeKind {
    Text,
    Space,
}

#[allow(dead_code)]
fn decode_text() -> NifResult<()> {
    Ok(())
}

#[allow(dead_code)]
fn decode_space() -> NifResult<()> {
    Ok(())
}

rustler::atoms! {
    atom_struct = "__struct__",
}

mod atoms {
    rustler::atoms! {
        r#type = "type",
        text,
        space,
        body,
        test,
        consequent,
        alternate,
        opts,
        args,
    }
}

include!("generated.rs");
