fn main() {
    let events = [1, 2, 3];
    let mut acc = 0;
    for event in events {
        acc += event;
    }
    println!("{acc}");
}
