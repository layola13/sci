// 311 - C-String Literals
// Rust 1.77+: let s = c"hello"; // null-terminated CString literal
use std::ffi::CStr;

fn main() {
    let s = c"hello";
    let len = s.count_bytes();
    println!("{len}");
}
