// 329 - Assert with Custom Message
// Rust: assert!(x > 0, "x must be positive, got {x}");
// assert_eq!(a, b, "values differ");
fn safe_divide(a: i32, b: i32) -> i32 {
    assert!(b != 0, "division by zero");
    assert!(a >= 0, "numerator must be non-negative");
    a / b
}

fn main() {
    let r = safe_divide(10, 2);
    println!("{r}");
}
