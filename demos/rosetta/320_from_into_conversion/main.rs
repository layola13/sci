// 320 - From/Into Conversion Trait
// Rust: impl From<A> for B → let b: B = a.into();
struct Celsius(f64);
struct Fahrenheit(f64);

impl From<Celsius> for Fahrenheit {
    fn from(c: Celsius) -> Self {
        Fahrenheit(c.0 * 9.0 / 5.0 + 32.0)
    }
}

fn main() {
    let boiling = Celsius(100.0);
    let f: Fahrenheit = boiling.into();
    println!("{}", f.0 as i32);
}
