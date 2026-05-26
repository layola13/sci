// 319 - Default Trait
// Rust: #[derive(Default)] or impl Default for T
struct Config {
    width: i32,
    height: i32,
    fullscreen: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config { width: 800, height: 600, fullscreen: false }
    }
}

fn main() {
    let c = Config::default();
    let custom = Config { width: 1920, ..Default::default() };
    println!("{}", c.width + custom.height);
}
