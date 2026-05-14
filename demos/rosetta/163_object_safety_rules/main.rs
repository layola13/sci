trait Draw {
    fn draw(&self) -> i32;
}

struct Item;

impl Draw for Item {
    fn draw(&self) -> i32 {
        4
    }
}

fn main() {
    let item = Item;
    println!("{}", item.draw());
}
