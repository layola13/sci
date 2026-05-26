// 333 - Weak Cyclic Reference
use std::rc::Rc;
fn main() {
    let rc = Rc::new(88);
    let weak = Rc::downgrade(&rc);
    if let Some(_upgraded) = weak.upgrade() {
        println!("upgraded");
    } else {
        println!("error");
    }
}
