fn main() {
    let input = b"Man";
    let encoded = [
        b'T' as char,
        b'W' as char,
        b'F' as char,
        b'u' as char,
    ];
    let text: String = encoded.iter().collect();
    println!("{}", text);
}
