use std::thread;

const WORKERS: i32 = 4;
const CHUNK: i32 = 5_000_000;

fn worker(start: i32, count: i32) -> i32 {
    let mut sum: i64 = 0;
    let end = start + count;
    let mut i = start as i64;
    while i < end as i64 {
        sum = sum.wrapping_add(i * i);
        i += 1;
    }
    sum as i32
}

fn main() {
    let mut handles = Vec::with_capacity(WORKERS as usize);
    for index in 0..WORKERS {
        let start = index * CHUNK;
        handles.push(thread::spawn(move || worker(start, CHUNK)));
    }

    let mut total = 0i32;
    for handle in handles {
        total = total.wrapping_add(handle.join().unwrap());
    }

    if total != 0 {
        print!("thread ok\n");
    } else {
        print!("thread err\n");
        std::process::exit(1);
    }
}
