// 326 - Lazy Static / OnceLock
// Rust: static ONCE: OnceLock<i32> = OnceLock::new();
use std::sync::OnceLock;

static GLOBAL: OnceLock<i32> = OnceLock::new();

fn get_global() -> i32 {
    *GLOBAL.get_or_init(|| 42)
}

fn main() {
    let a = get_global();
    let b = get_global(); // same value, initialized once
    println!("{}", a + b);
}
