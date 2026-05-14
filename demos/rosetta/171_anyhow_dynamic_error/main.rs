fn fail() -> Result<&'static str, &'static str> {
    Err("anyhow")
}

fn main() {
    let result = fail().map(|msg| msg.len());
    println!("{}", result.unwrap_or(0));
}
