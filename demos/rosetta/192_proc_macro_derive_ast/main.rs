#[derive(Clone, Copy)]
struct Triple {
    left: i32,
    mid: i32,
    right: i32,
}

fn derive_copy(src: &Triple) -> (Triple, i32) {
    let copy = *src;
    let total = copy.left + copy.mid + copy.right;
    (copy, total)
}

fn main() {
    let triple = Triple {
        left: 1,
        mid: 2,
        right: 3,
    };
    let (copy, total) = derive_copy(&triple);
    let ok = copy.left == 1 && copy.mid == 2 && copy.right == 3 && total == 6;
    println!("{}", if ok { total } else { -1 });
}

