#[cfg(target_arch = "x86_64")]
fn main() {
    println!("4");
}

#[cfg(not(target_arch = "x86_64"))]
fn main() {
    println!("4");
}
