thread_local! {
    static VALUE: std::cell::Cell<i32> = std::cell::Cell::new(6);
}

fn main() {
    VALUE.with(|v| println!("{}", v.get()));
}
