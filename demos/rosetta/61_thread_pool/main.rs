use std::thread;

fn main() {
    let a = thread::spawn(|| 2);
    let b = thread::spawn(|| 3);
    let total = a.join().unwrap() + b.join().unwrap();
    println!("{total}");
}
