// 315 - Async Closures (Rust 2024)
// Rust: async || { ... } capturing environment
// Simulated via state machine that captures env
struct AsyncAdd {
    env_val: i32,
    state: u32,
}

impl AsyncAdd {
    fn poll(&mut self) -> Option<i32> {
        match self.state {
            0 => { self.state = 1; None }
            1 => { self.state = 2; Some(self.env_val + 10) }
            _ => None,
        }
    }
}

fn main() {
    let captured = 5;
    let mut fut = AsyncAdd { env_val: captured, state: 0 };
    assert!(fut.poll().is_none()); // pending
    let result = fut.poll().unwrap(); // ready
    println!("{result}");
}
