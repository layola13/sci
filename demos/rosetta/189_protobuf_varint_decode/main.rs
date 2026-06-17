fn decode_varint(bytes: &[u8]) -> u32 {
    let mut acc = 0u32;
    let mut shift = 0u32;

    for &byte in bytes.iter().take(3) {
        acc += u32::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            break;
        }
        shift += 7;
    }

    acc
}

fn main() {
    let buf = [6u8, 0, 0];
    println!("{}", decode_varint(&buf));
}

