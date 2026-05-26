// 332 - Cell Interior Mutability
use std::cell::Cell;
fn main() {
    let cell = Cell::new(42);
    cell.set(100);
    println!("{}", cell.get());
}
