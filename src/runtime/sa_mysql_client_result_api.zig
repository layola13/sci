const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_mysql_client.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_OK = @import("sa_mysql_client.zig").SA_STD_OK;
const alloc = @import("sa_mysql_client.zig").alloc;
const connFrom = @import("sa_mysql_client.zig").connFrom;
const resultFrom = @import("sa_mysql_client.zig").resultFrom;
const u64ToUsize = @import("sa_mysql_client.zig").u64ToUsize;

pub export fn sa_mysql_error_message(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = conn.err_msg.ptr;
    ll.* = conn.err_msg.len;
    return SA_STD_OK;
}

pub export fn sa_mysql_server_version(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const conn = connFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = conn.server_version.ptr;
    ll.* = conn.server_version.len;
    return SA_STD_OK;
}

pub export fn sa_mysql_connection_id(handle: u64) u32 {
    const conn = connFrom(handle) orelse return 0;
    return conn.connection_id;
}

pub export fn sa_mysql_result_free(handle: u64) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const conn = result.conn;
    for (conn.results.items, 0..) |r, i| {
        if (r == result) {
            _ = conn.results.orderedRemove(i);
            break;
        }
    }
    result.deinit();
    alloc.destroy(result);
    return SA_STD_OK;
}

pub export fn sa_mysql_result_has_result_set(handle: u64) u32 {
    const result = resultFrom(handle) orelse return 0;
    return if (result.has_result_set) 1 else 0;
}

pub export fn sa_mysql_result_column_count(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return @intCast(result.columns.len);
}

pub export fn sa_mysql_result_column_name(handle: u64, idx: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const i = u64ToUsize(idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (i >= result.columns.len) return SA_STD_ERR_INVALID_ARGUMENT;
    pp.* = result.columns[i].name.ptr;
    ll.* = result.columns[i].name.len;
    return SA_STD_OK;
}

pub export fn sa_mysql_result_column_type(handle: u64, idx: u64) u32 {
    const result = resultFrom(handle) orelse return 0xFFFF_FFFF;
    const i = u64ToUsize(idx) orelse return 0xFFFF_FFFF;
    if (i >= result.columns.len) return 0xFFFF_FFFF;
    return result.columns[i].type_code;
}

pub export fn sa_mysql_result_row_count(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return @intCast(result.rows.items.len);
}

pub export fn sa_mysql_result_next(handle: u64, out_row: ?*u64) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const slot = out_row orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (result.cursor >= result.rows.items.len) return 0;
    slot.* = @intCast(result.cursor);
    result.cursor += 1;
    return 1;
}

pub export fn sa_mysql_result_value(
    handle: u64,
    row_idx: u64,
    col_idx: u64,
    out_ptr: ?*?[*]const u8,
    out_len: ?*u64,
    out_is_null: ?*u32,
) i32 {
    const result = resultFrom(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const pp = out_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const ll = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const nn = out_is_null orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const r = u64ToUsize(row_idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const c = u64ToUsize(col_idx) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    if (r >= result.rows.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const row = result.rows.items[r];
    if (c >= row.len) return SA_STD_ERR_INVALID_ARGUMENT;
    if (row[c]) |bytes| {
        pp.* = bytes.ptr;
        ll.* = bytes.len;
        nn.* = 0;
    } else {
        pp.* = "".ptr;
        ll.* = 0;
        nn.* = 1;
    }
    return SA_STD_OK;
}

pub export fn sa_mysql_affected_rows(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return result.affected_rows;
}

pub export fn sa_mysql_last_insert_id(handle: u64) u64 {
    const result = resultFrom(handle) orelse return 0;
    return result.last_insert_id;
}

pub export fn sa_mysql_result_warnings(handle: u64) u32 {
    const result = resultFrom(handle) orelse return 0;
    return result.warning_count;
}
