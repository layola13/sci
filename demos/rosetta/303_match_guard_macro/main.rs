// 303 - Match Guard Pattern
// Rust: match with if guards on bindings
fn classify(n: i32) -> &'static str {
    match n {
        x if x < 0 => "negative",
        x if x == 0 => "zero",
        x if x <= 10 => "small",
        _ => "large",
    }
}

fn main() {
    let a = classify(-3);
    let b = classify(0);
    let c = classify(7);
    let d = classify(99);
    // verify: a=negative, b=zero, c=small, d=large
    println!("{a},{b},{c},{d}");
}
