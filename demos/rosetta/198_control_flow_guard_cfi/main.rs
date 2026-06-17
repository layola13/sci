#[repr(C)]
struct FnSlot {
    data: i32,
    vtable: fn(i32) -> i32,
}

fn guarded_target(x: i32) -> i32 {
    x + 1
}

fn main() {
    let slot = FnSlot {
        data: 0,
        vtable: guarded_target,
    };
    let call_slot = slot.vtable;
    let expected = guarded_target as fn(i32) -> i32;
    let ok = std::ptr::fn_addr_eq(call_slot, expected) && call_slot(1) == 2;
    println!("{}", if ok { 2 } else { -1 });
}

