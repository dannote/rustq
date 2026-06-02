#![allow(dead_code)]
#![allow(non_snake_case)]

use rustler::{Atom, Encoder, Env, NifResult, NifStruct, ResourceArc, Term};
use std::sync::OnceLock;

struct Node;

rustler::atoms! {
    atom_struct = "__struct__",
}

mod atoms {
    rustler::atoms! {
        r#type = "type",
        body,
        test,
        consequent,
        alternate,
    }
}

include!("generated.rs");
