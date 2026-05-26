// 304 - While-Let Pattern
// Rust: while let Some(x) = iter.next() { sum += x; }
fn main() {
    let items = [Some(1), Some(2), Some(3), None];
    let mut sum = 0;
    let mut idx = 0;
    while let Some(Some(val)) = items.get(idx).map(|x| *x) {
        sum += val;
        idx += 1;
    }
    println!("{sum}");
}
