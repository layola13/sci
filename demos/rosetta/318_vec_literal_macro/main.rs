// 318 - vec![] Literal Macro
// Rust: let v = vec![1, 2, 3]; // heap-allocated, length-tracked
fn main() {
    let v = vec![10i32, 20, 30, 40];
    let len = v.len();
    let sum: i32 = v.iter().sum();
    println!("{len},{sum}");
}
