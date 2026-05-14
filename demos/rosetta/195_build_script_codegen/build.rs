use std::fs;
use std::path::Path;

fn main() {
    let generated = r#"pub const GENERATED: &str = "build output";
"#;
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let out = Path::new(&out_dir).join("generated.rs");
    fs::write(out, generated).unwrap();
    println!("cargo:rerun-if-changed=build.rs");
}
