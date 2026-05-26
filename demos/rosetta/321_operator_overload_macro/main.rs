// 321 - Operator Overloading (Add trait)
// Rust: impl Add for Vec2
#[derive(Copy, Clone)]
struct Vec2 { x: i32, y: i32 }

impl std::ops::Add for Vec2 {
    type Output = Vec2;
    fn add(self, other: Vec2) -> Vec2 {
        Vec2 { x: self.x + other.x, y: self.y + other.y }
    }
}

fn main() {
    let a = Vec2 { x: 1, y: 2 };
    let b = Vec2 { x: 3, y: 4 };
    let c = a + b;
    println!("{},{}", c.x, c.y);
}
