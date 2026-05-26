// 312 - dbg! Macro
// Rust: dbg!(x) prints file:line, expression, value, returns value
fn compute(x: i32) -> i32 {
    let a = dbg!(x * 2);
    let b = dbg!(a + 1);
    b
}

fn main() {
    let result = compute(5);
    println!("{result}");
}
