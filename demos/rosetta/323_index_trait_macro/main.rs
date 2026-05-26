// 323 - Index Trait
// Rust: impl Index<usize> for Grid
struct Grid {
    data: Vec<i32>,
    cols: usize,
}

impl std::ops::Index<(usize, usize)> for Grid {
    type Output = i32;
    fn index(&self, (r, c): (usize, usize)) -> &i32 {
        &self.data[r * self.cols + c]
    }
}

fn main() {
    let g = Grid { data: vec![1, 2, 3, 4, 5, 6], cols: 3 };
    let val = g[(1, 2)]; // row 1, col 2 → 6
    println!("{val}");
}
