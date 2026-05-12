use std::sync::mpsc;

fn main() {
    let (tx, rx) = mpsc::channel();
    tx.send(8).unwrap();
    let value = rx.recv().unwrap();
    println!("{value}");
}
