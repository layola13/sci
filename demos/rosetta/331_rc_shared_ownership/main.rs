// 331 - Rc Shared Ownership
use std::rc::Rc;
fn main() {
    let rc1 = Rc::new(42);
    let rc2 = Rc::clone(&rc1);
    println!("{},{}", *rc1, *rc2);
}
