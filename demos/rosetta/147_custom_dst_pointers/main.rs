struct Blob {
    len: usize,
    data: [u8],
}

fn main() {
    let bytes: &[u8] = b"abc";
    println!("{}", bytes.len());
}
