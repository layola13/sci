// 322 - Deref Coercion
// Rust: impl Deref for SmartPtr<T> { Target = T }
struct SmartPtr {
    data: Box<i32>,
}

impl std::ops::Deref for SmartPtr {
    type Target = i32;
    fn deref(&self) -> &i32 {
        &self.data
    }
}

fn print_val(v: &i32) -> i32 {
    *v + 10
}

fn main() {
    let sp = SmartPtr { data: Box::new(42) };
    // Deref coercion: &SmartPtr → &i32
    let result = print_val(&sp);
    println!("{result}");
}
