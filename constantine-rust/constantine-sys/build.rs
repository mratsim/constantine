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

    Command::new("nimble")
        .env("CC", "clang")
        .arg("make_lib_rust")
        .current_dir(root_dir)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .expect("failed to execute process");

    println!("cargo:rustc-link-search=native={}", out_dir.display());

    // On windows stable channel (msvc) expects constantine.lib
    // while stable-gnu channel (gcc) expects libconstantine.a
    // hence we use +verbatim
    #[cfg(target_family = "windows")]
    println!("cargo:rustc-link-lib=static:+verbatim=constantine.lib");

    #[cfg(target_family = "unix")]
    println!("cargo:rustc-link-lib=static:+verbatim=libconstantine.a");

    // Avoid full recompilation
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-changed=src");
    println!(
        "cargo:rerun-if-changed={}",
        root_dir.join(".cargo").join("config.toml").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        root_dir.join("Cargo.toml").display()
    );
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
