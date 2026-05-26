// 328 - cfg!() Runtime Check
// Rust: if cfg!(target_arch = "x86_64") { ... }
fn get_arch() -> &'static str {
    if cfg!(target_arch = "x86_64") {
        "x86_64"
    } else if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else {
        "unknown"
    }
}

fn main() {
    let arch = get_arch();
    println!("{arch}");
}
