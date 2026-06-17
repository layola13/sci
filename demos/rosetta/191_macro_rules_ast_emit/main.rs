macro_rules! capture {
    ($dst:ident, $value:expr) => {
        let $dst = $value;
    };
}

macro_rules! sum3 {
    ($out:ident, $a:expr, $b:expr, $c:expr) => {
        let $out = $a + $b + $c;
    };
}

macro_rules! build {
    ($left:expr, $middle:expr, $right:expr, $mirror:ident, $result:ident) => {
        sum3!($result, $left, $middle, $right);
        capture!($mirror, $result);
    };
}

fn main() {
    let left = 1;
    let middle = 2;
    let right = 3;
    build!(left, middle, right, mirror, result);
    println!("{}", result + mirror);
}

