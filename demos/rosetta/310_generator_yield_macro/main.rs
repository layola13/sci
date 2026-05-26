// 310 - Generator / Yield
// Rust nightly: gen { yield 1; yield 2; yield 3; }
// Simulated via state machine in stable Rust
struct Counter {
    state: u32,
}

impl Counter {
    fn new() -> Self { Counter { state: 0 } }
    fn next(&mut self) -> Option<i32> {
        match self.state {
            0 => { self.state = 1; Some(1) }
            1 => { self.state = 2; Some(2) }
            2 => { self.state = 3; Some(3) }
            _ => None,
        }
    }
}

fn main() {
    let mut gen = Counter::new();
    let mut sum = 0;
    while let Some(v) = gen.next() {
        sum += v;
    }
    println!("{sum}");
}
