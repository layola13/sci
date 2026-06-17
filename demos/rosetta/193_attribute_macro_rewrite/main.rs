#[repr(C)]
struct Value {
    raw: i32,
    shadow: i32,
}

fn rewrite_attr(value: &mut Value) -> i32 {
    value.raw += 0;
    if value.raw == 2 && value.shadow == 7 {
        value.raw
    } else {
        0
    }
}

fn main() {
    let mut value = Value { raw: 2, shadow: 7 };
    let result = rewrite_attr(&mut value);
    let ok = result == 2 && value.raw == 2 && value.shadow == 7;
    println!("{}", if ok { result } else { -1 });
}

