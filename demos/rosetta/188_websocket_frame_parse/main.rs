#[repr(C)]
struct Frame {
    b0: u8,
    b1: u8,
    mask0: u8,
    mask1: u8,
    mask2: u8,
    mask3: u8,
    len: i32,
    payload0: u8,
    payload1: u8,
    payload2: u8,
    opcode: u8,
    fin: u8,
    masked: u8,
    payload_sum: i32,
}

fn parse_frame(frame: &mut Frame) -> bool {
    let fin = frame.b0 & 0x80;
    let opcode = frame.b0 & 0x0f;
    let rsv = frame.b0 & 0x70;
    let masked = frame.b1 & 0x80;
    let len = frame.b1 & 0x7f;
    let payload_sum = i32::from(frame.payload0) + i32::from(frame.payload1) + i32::from(frame.payload2);
    frame.fin = fin;
    frame.opcode = opcode;
    frame.masked = masked;
    frame.len = i32::from(len);
    frame.payload_sum = payload_sum;
    fin == 0x80 && opcode == 1 && rsv == 0 && masked == 0 && len == 3
}

fn main() {
    let mut frame = Frame {
        b0: 0x81,
        b1: 0x03,
        mask0: 0,
        mask1: 0,
        mask2: 0,
        mask3: 0,
        len: 0,
        payload0: 1,
        payload1: 2,
        payload2: 3,
        opcode: 0,
        fin: 0,
        masked: 0,
        payload_sum: 0,
    };
    println!("{}", if parse_frame(&mut frame) { 1 } else { 0 });
}

