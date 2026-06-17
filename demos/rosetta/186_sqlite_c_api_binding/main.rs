use std::ffi::c_void;
use std::os::raw::c_int;

unsafe extern "C" {
    fn sqlite3_prepare(
        sqlite: *mut c_void,
        sql: *const u8,
        len: c_int,
        stmt_out: *mut *mut c_void,
    ) -> c_int;
    fn sqlite3_step(stmt: *mut c_void) -> c_int;
    fn sqlite3_finalize(stmt: *mut c_void) -> c_int;
}

#[repr(C)]
struct Row {
    id: c_int,
    count: c_int,
    total: c_int,
}

#[repr(C)]
struct StmtSlot {
    db: *mut c_void,
    sql: *const u8,
    stmt: *mut c_void,
    code: c_int,
}

fn main() {
    let mut row = Row {
        id: 7,
        count: 1,
        total: 0,
    };
    row.total = row.id + row.count;
    let sql = b"insert into demo values (?, ?)\0";
    let mut stmt = StmtSlot {
        db: std::ptr::null_mut(),
        sql: sql.as_ptr(),
        stmt: std::ptr::null_mut(),
        code: 0,
    };
    let prepare = unsafe { sqlite3_prepare(stmt.db, stmt.sql, 32, &mut stmt.stmt) };
    let step = unsafe { sqlite3_step(stmt.stmt) };
    let finalize = unsafe { sqlite3_finalize(stmt.stmt) };
    let ok = prepare == 0 && step != 0 && finalize == 0 && row.total == 8;
    println!("{}", if ok { row.total } else { -1 });
}

