// 314 - Tail Call (become keyword - experimental)
// Rust: become f(x) for guaranteed TCO
// Simulated: tail-recursive factorial
fn fact_acc(n: u64, acc: u64) -> u64 {
    if n <= 1 { acc } else { fact_acc(n - 1, n * acc) }
}

fn main() {
    let result = fact_acc(10, 1);
    println!("{result}");
}
