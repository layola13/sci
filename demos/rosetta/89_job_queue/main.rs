use std::collections::VecDeque;

fn main() {
    let mut queue = VecDeque::new();
    queue.push_back(5);
    queue.push_back(7);
    println!("{}", queue.pop_front().unwrap() + queue.pop_front().unwrap());
}
