// 313 - matches! Macro
// Rust: matches!(x, Some(v) if v > 0) → bool
enum Status { Active(i32), Inactive, Error(String) }

fn is_active_positive(s: &Status) -> bool {
    matches!(s, Status::Active(v) if *v > 0)
}

fn main() {
    let items = vec![
        Status::Active(5),
        Status::Inactive,
        Status::Active(-1),
        Status::Error("bad".to_string()),
    ];
    let count = items.iter().filter(|s| is_active_positive(s)).count();
    println!("{count}");
}
