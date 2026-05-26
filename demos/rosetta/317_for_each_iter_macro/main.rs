// 317 - For-Each Iterator Macro
// Rust: for item in &collection { sum += item; }
fn main() {
    let data = [10, 20, 30, 40, 50];
    let mut sum = 0;
    for &val in data.iter() {
        sum += val;
    }
    println!("{sum}");
}
