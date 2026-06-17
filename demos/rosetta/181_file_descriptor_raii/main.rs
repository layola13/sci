use std::os::raw::c_int;

unsafe extern "C" {
    fn fd_open(path: *const u8) -> c_int;
    fn fd_read(fd: c_int) -> c_int;
    fn fd_close(fd: c_int) -> c_int;
}

#[repr(C)]
struct Handle {
    fd: c_int,
    state: c_int,
}

fn main() {
    let mut handle = Handle { fd: 0, state: 0 };
    let path = b"/dev/null\0";
    let fd = unsafe { fd_open(path.as_ptr()) };
    handle.fd = fd;
    let value = unsafe { fd_read(fd) };
    let closed = unsafe { fd_close(fd) };
    let ok = fd != 0 && value == 3 && closed == 0;
    println!("{}", if ok { 3 } else { -1 });
}

