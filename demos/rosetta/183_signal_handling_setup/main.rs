use std::os::raw::c_int;

unsafe extern "C" {
    fn signal(sig: c_int, handler: extern "C" fn(c_int) -> c_int) -> c_int;
}

#[repr(C)]
struct SignalSlot {
    num: c_int,
    handler: extern "C" fn(c_int) -> c_int,
}

extern "C" fn handle_signal(sig: c_int) -> c_int {
    sig
}

fn main() {
    let slot = SignalSlot {
        num: 2,
        handler: handle_signal,
    };
    let registered = unsafe { signal(2, slot.handler) };
    let ok = registered == 2 && slot.num == 2;
    println!("{}", if ok { 2 } else { -1 });
}

