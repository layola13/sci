fn main() {
    let mut sum: u64 = 0;
    let limit = 100_000_000;
    let mut i = 0;
    while i < limit {
        sum = sum.wrapping_add(i * i);
        i += 1;
    }
    println!("Result: {}", sum);
}
