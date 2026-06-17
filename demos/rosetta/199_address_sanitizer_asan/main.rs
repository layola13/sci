fn main() {
    let buf = [1u8, 2, 3, 4, 0];
    let sum = buf[0] + buf[3];
    let ok = buf[0] == 1 && buf[3] == 4 && buf[4] == 0;
    println!("{}", if ok { sum } else { 0 });
}

