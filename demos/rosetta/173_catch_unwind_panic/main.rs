fn main() {
    let result = std::panic::catch_unwind(|| {
        let payload = "stop";
        panic!("{}", payload);
    });

    if result.is_ok() {
        println!("ok");
    }
}
