// 324 - Drop Guard / RAII Scope
// Rust: let _guard = Guard { ... }; // drops at scope end
struct LockGuard {
    id: i32,
}

impl Drop for LockGuard {
    fn drop(&mut self) {
        // release lock
    }
}

fn do_work() -> i32 {
    let _g = LockGuard { id: 1 };
    42 // _g dropped here
}

fn main() {
    let result = do_work();
    println!("{result}");
}
