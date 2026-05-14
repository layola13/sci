fn main() {
    let parked = false;
    let woke = true;
    println!("{}", if parked || woke { 1 } else { 0 });
}
