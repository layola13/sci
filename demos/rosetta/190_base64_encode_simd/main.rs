const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn encode_block(input: &[u8; 3]) -> [u8; 4] {
    let q0 = input[0] / 4;
    let q1 = (input[0] % 4) * 16 + input[1] / 16;
    let q2 = (input[1] % 16) * 4 + input[2] / 64;
    let q3 = input[2] % 64;
    [
        B64[usize::from(q0)],
        B64[usize::from(q1)],
        B64[usize::from(q2)],
        B64[usize::from(q3)],
    ]
}

fn main() {
    let encoded = encode_block(b"Man");
    let text = std::str::from_utf8(&encoded).unwrap();
    println!("{text}");
}

