// 327 - thread_local! Macro
// Rust: thread_local! { static COUNTER: Cell<i32> = Cell::new(0); }
use std::cell::Cell;

thread_local! {
    static COUNTER: Cell<i32> = Cell::new(0);
}

fn increment() -> i32 {
    COUNTER.with(|c| {
        let v = c.get() + 1;
        c.set(v);
        v
    })
}

fn main() {
    let a = increment();
    let b = increment();
    let c = increment();
    println!("{}", a + b + c);
}
