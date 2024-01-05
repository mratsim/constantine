#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

#[cfg(target_pointer_width = "64")]
include!("bindings64.rs");
#[cfg(target_pointer_width = "32")]
include!("bindings32.rs");