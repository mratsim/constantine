use std::env;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let cargo_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let root_dir = cargo_dir
        .parent()
        .expect("constantine-sys is nested")
        .parent()
        .expect("constantine-rust is nested");

    println!("Building Constantine library ...");

    let mut cmd = Command::new("nimble");
    let status = match cmd
        .env("CC", "clang")
        .arg("make_lib_rust")
        .current_dir(root_dir)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status() {
            Ok(status) => status,
            Err(error) => {
                if error.kind() == std::io::ErrorKind::NotFound {
                    panic!("nimble not found, please install Nim: {error}");
                } else {
                    panic!("nimble execution failed: {error}");
                }
            }
        };
    if !status.success() {
        panic!("failed to build with {cmd:?}: {status}");
    }

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=constantine");

    // Recompile when Nim sources changed
    println!("cargo:rerun-if-changed=build.rs");
    println!(
        "cargo:rerun-if-changed={}",
        root_dir.join("constantine").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        root_dir.join("bindings").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        root_dir.join("include").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        root_dir.join("constantine.nimble").display()
    );
}
