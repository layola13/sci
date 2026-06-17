use std::os::raw::c_int;

unsafe extern "C" {
    fn fd_open(path: *const u8) -> c_int;
    fn fd_close(fd: c_int) -> c_int;
    fn mmap(fd: c_int, len: c_int) -> *const u8;
    fn munmap(map: *const u8, len: c_int) -> c_int;
}

#[repr(C)]
struct Map {
    fd: c_int,
    ptr: *const u8,
    len: c_int,
}

fn main() {
    let mut map = Map {
        fd: 0,
        ptr: std::ptr::null(),
        len: 4,
    };
    let path = b"/dev/zero\0";
    let fd = unsafe { fd_open(path.as_ptr()) };
    let ptr = unsafe { mmap(fd, 4) };
    map.fd = fd;
    map.ptr = ptr;
    let byte = unsafe { *ptr };
    let unmapped = unsafe { munmap(ptr, 4) };
    let closed = unsafe { fd_close(fd) };
    let ok = byte == 0 && unmapped == 0 && closed == 0 && fd != 0 && fd + 1 == 4;
    println!("{}", if ok { 4 } else { -1 });
}

