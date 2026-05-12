fn main() {
    let jobs = [1, 2, 3, 4];
    let mut done = 0;
    for job in jobs {
        done += job;
    }
    println!("{done}");
}
