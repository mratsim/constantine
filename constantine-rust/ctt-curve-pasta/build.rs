use std::env;
use std::path::PathBuf;
use std::process::{Command, Stdio};

const LIB_NAME: &str = "constantine_pasta";

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let cargo_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let root_dir = cargo_dir
        .parent()
        .expect("rust library is nested")
        .parent()
        .expect("constantine-rust is nested");

    let rust_lib_name = cargo_dir
        .file_name()
        .expect("Directory exist");

    println!("Building Constantine library ...");

    Command::new("nimble")
            .arg("make_lib_rust")
            .env("CTT_RUST_LIB", rust_lib_name)
            .current_dir(root_dir)
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()
            .expect("failed to execute process");

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static={}", LIB_NAME);
    // Avoid full recompilation
    // println!("cargo:rerun-if-changed={}", root_dir.join("constantine").display());
}