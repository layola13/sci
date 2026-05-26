// 325 - Loop Break with Value
// Rust: let result = loop { if condition { break value; } };
fn find_first_square_above(n: i32) -> i32 {
    let mut i = 1;
    loop {
        let sq = i * i;
        if sq > n {
            break sq;
        }
        i += 1;
    }
}

fn main() {
    let result = find_first_square_above(20);
    println!("{result}");
}
