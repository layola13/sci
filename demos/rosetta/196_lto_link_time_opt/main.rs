#[inline(always)]
fn leaf(a: i32, b: i32) -> i32 {
    a + b
}

#[inline(always)]
fn inner(x: i32) -> i32 {
    let one = leaf(x, 1);
    let two = leaf(x, 2);
    let three = leaf(3, 4);
    one + two + three
}

#[inline(never)]
fn cold_path(x: i32) -> i32 {
    inner(x) + leaf(5, 6)
}

fn main() {
    let hot = inner(1);
    let cold = cold_path(2);
    println!("{}", hot + cold);
}

