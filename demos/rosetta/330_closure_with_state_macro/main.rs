// 330 - Stateful Closure (FnMut)
// Rust: let mut counter = || { count += 1; count };
fn make_counter(start: i32) -> impl FnMut() -> i32 {
    let mut count = start;
    move || {
        count += 1;
        count
    }
}

fn main() {
    let mut c = make_counter(0);
    let a = c();
    let b = c();
    let c_val = c();
    println!("{}", a + b + c_val);
}
