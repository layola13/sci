const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_PERMISSION_DENIED = @import("../sa_std.zig").SA_STD_ERR_PERMISSION_DENIED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const TimeDate = @import("../sa_std.zig").TimeDate;
const appendFour = @import("../sa_std.zig").appendFour;
const appendIsoUtc = @import("../sa_std.zig").appendIsoUtc;
const appendTwo = @import("../sa_std.zig").appendTwo;
const civilParts = @import("../sa_std.zig").civilParts;
const constBytes = @import("../sa_std.zig").constBytes;
const daysFromCivil = @import("../sa_std.zig").daysFromCivil;
const fillUtcNow = @import("../sa_std.zig").fillUtcNow;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const monotonicNowNs = @import("../sa_std.zig").monotonicNowNs;
const monthNames = @import("../sa_std.zig").monthNames;
const openOwnedBuffer = @import("../sa_std.zig").openOwnedBuffer;
const policyAllows = @import("../sa_std.zig").policyAllows;
const sio = @import("../sa_std.zig").sio;
const weekdayNames = @import("../sa_std.zig").weekdayNames;

pub export fn sa_time_instant_ns() u64 {
    if (!policyAllows(.time)) return 0;
    return monotonicNowNs() catch return 0;
}

pub export fn sa_time_unix_s() i64 {
    if (!policyAllows(.time)) return 0;
    return sio.timestampSeconds();
}

pub export fn sa_time_unix_ms() i64 {
    if (!policyAllows(.time)) return 0;
    return std.Io.Clock.real.now(sio.io()).toMilliseconds();
}

pub export fn sa_time_iso_from_unix_ms(ms: i64) u64 {
    const ms_per_day: i64 = 86400000;
    // Floored division: afternoon negatives land on the right day.
    var days = @divFloor(ms, ms_per_day);
    var day_ms = @mod(ms, ms_per_day);
    if (day_ms < 0) {
        day_ms += ms_per_day;
        days -= 1;
    }
    // Hinnant civil_from_days (days since 1970-01-01 -> y/m/d).
    const z: i64 = days + 719468;
    const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const day: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month: i64 = if (mp < 10) mp + 3 else mp - 9;
    const year: i64 = if (month <= 2) y + 1 else y;
    const hour: i64 = @divFloor(day_ms, 3600000);
    const minute: i64 = @divFloor(@mod(day_ms, 3600000), 60000);
    const second: i64 = @divFloor(@mod(day_ms, 60000), 1000);
    const milli: i64 = @mod(day_ms, 1000);
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    appendIsoUtc(&out, year, month, day, hour, minute, second, milli) catch return 0;
    return openOwnedBuffer(out.toOwnedSlice() catch return 0) catch return 0;
}

pub export fn sa_time_parse_iso(iso_ptr: ?[*]const u8, iso_len: u64, out_ms: ?*i64) i32 {
    const out = out_ms orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    out.* = 0;
    const bytes = constBytes(iso_ptr, iso_len) catch |err| return finishErr(err);
    const bad = finish(SA_STD_ERR_INVALID_ARGUMENT);
    var p: usize = 0;
    const take = struct {
        fn digits(b: []const u8, pos: *usize, n: usize) ?i64 {
            if (pos.* + n > b.len) return null;
            var v: i64 = 0;
            for (b[pos.*..][0..n]) |c| {
                if (c < '0' or c > '9') return null;
                v = v * 10 + @as(i64, c - '0');
            }
            pos.* += n;
            return v;
        }
    }.digits;
    const year = take(bytes, &p, 4) orelse return bad;
    if (p >= bytes.len or bytes[p] != '-') return bad;
    p += 1;
    const month = take(bytes, &p, 2) orelse return bad;
    if (p >= bytes.len or bytes[p] != '-') return bad;
    p += 1;
    const day = take(bytes, &p, 2) orelse return bad;
    var hour: i64 = 0;
    var minute: i64 = 0;
    var second: i64 = 0;
    var milli: i64 = 0;
    if (p < bytes.len) {
        if (bytes[p] != 'T' and bytes[p] != 't' and bytes[p] != ' ') return bad;
        p += 1;
        hour = take(bytes, &p, 2) orelse return bad;
        if (p >= bytes.len or bytes[p] != ':') return bad;
        p += 1;
        minute = take(bytes, &p, 2) orelse return bad;
        if (p >= bytes.len or bytes[p] != ':') return bad;
        p += 1;
        second = take(bytes, &p, 2) orelse return bad;
        if (p < bytes.len and bytes[p] == '.') {
            p += 1;
            const fstart = p;
            while (p < bytes.len and bytes[p] >= '0' and bytes[p] <= '9') : (p += 1) {}
            const flen = p - fstart;
            if (flen == 0 or flen > 3) return bad;
            var f: i64 = 0;
            for (bytes[fstart..p]) |c| f = f * 10 + @as(i64, c - '0');
            milli = if (flen == 1) f * 100 else if (flen == 2) f * 10 else f;
        }
    }
    var offset_min: i64 = 0;
    if (p < bytes.len) {
        if (bytes[p] == 'Z' or bytes[p] == 'z') {
            p += 1;
        } else if (bytes[p] == '+' or bytes[p] == '-') {
            const neg = bytes[p] == '-';
            p += 1;
            const oh = take(bytes, &p, 2) orelse return bad;
            if (p >= bytes.len or bytes[p] != ':') return bad;
            p += 1;
            const om = take(bytes, &p, 2) orelse return bad;
            if (oh > 23 or om > 59) return bad;
            offset_min = oh * 60 + om;
            if (neg) offset_min = -offset_min;
        } else {
            return bad;
        }
    }
    if (p != bytes.len) return bad;
    if (month < 1 or month > 12) return bad;
    const leap = @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
    const dim: i64 = switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        else => if (leap) 29 else 28,
    };
    if (day < 1 or day > dim) return bad;
    if (hour > 23 or minute > 59 or second > 59) return bad;
    // days_from_civil (Hinnant), April-based.
    const y: i64 = if (month <= 2) year - 1 else year;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = @mod(month - 3, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const days: i64 = era * 146097 + doe - 719468;
    out.* = ((days * 86400 + hour * 3600 + minute * 60 + second) * 1000 + milli) - offset_min * 60000;
    return finish(SA_STD_OK);
}

pub export fn sa_time_get_full_year(ms: i64) i64 {
    return civilParts(ms).year;
}

pub export fn sa_time_get_month(ms: i64) i64 {
    return civilParts(ms).month - 1;
}

pub export fn sa_time_get_date(ms: i64) i64 {
    return civilParts(ms).day;
}

pub export fn sa_time_get_hours(ms: i64) i64 {
    return civilParts(ms).hour;
}

pub export fn sa_time_get_minutes(ms: i64) i64 {
    return civilParts(ms).minute;
}

pub export fn sa_time_get_seconds(ms: i64) i64 {
    return civilParts(ms).second;
}

pub export fn sa_time_get_milliseconds(ms: i64) i64 {
    return civilParts(ms).milli;
}

pub export fn sa_time_get_day(ms: i64) i64 {
    const days = civilParts(ms).days;
    return @mod(days + 4, 7);
}

pub export fn sa_time_format_utc(ms: i64, fmt_id: u64) u64 {
    if (fmt_id > 3) {
        const empty = std.heap.page_allocator.alloc(u8, 0) catch return 0;
        return openOwnedBuffer(empty) catch return 0;
    }
    const c = civilParts(ms);
    const wday: usize = @as(usize, @intCast(@mod(c.days + 4, 7)));
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    switch (fmt_id) {
        // "Wed Jan 01 2020 00:00:00 GMT+0000 (Coordinated Universal Time)"
        0 => {
            out.appendSlice(weekdayNames[wday]) catch return 0;
            out.append(' ') catch return 0;
            out.appendSlice(monthNames[@as(usize, @intCast(c.month - 1))]) catch return 0;
            out.append(' ') catch return 0;
            appendTwo(&out, c.day) catch return 0;
            out.append(' ') catch return 0;
            appendFour(&out, c.year) catch return 0;
            out.append(' ') catch return 0;
            appendTwo(&out, c.hour) catch return 0;
            out.append(':') catch return 0;
            appendTwo(&out, c.minute) catch return 0;
            out.append(':') catch return 0;
            appendTwo(&out, c.second) catch return 0;
            out.appendSlice(" GMT+0000 (Coordinated Universal Time)") catch return 0;
        },
        // "Wed Jan 01 2020"
        1 => {
            out.appendSlice(weekdayNames[wday]) catch return 0;
            out.append(' ') catch return 0;
            out.appendSlice(monthNames[@as(usize, @intCast(c.month - 1))]) catch return 0;
            out.append(' ') catch return 0;
            appendTwo(&out, c.day) catch return 0;
            out.append(' ') catch return 0;
            appendFour(&out, c.year) catch return 0;
        },
        // "00:00:00 GMT+0000 (Coordinated Universal Time)"
        2 => {
            appendTwo(&out, c.hour) catch return 0;
            out.append(':') catch return 0;
            appendTwo(&out, c.minute) catch return 0;
            out.append(':') catch return 0;
            appendTwo(&out, c.second) catch return 0;
            out.appendSlice(" GMT+0000 (Coordinated Universal Time)") catch return 0;
        },
        // "Wed, 01 Jan 2020 00:00:00 GMT"
        3 => {
            out.appendSlice(weekdayNames[wday]) catch return 0;
            out.appendSlice(", ") catch return 0;
            appendTwo(&out, c.day) catch return 0;
            out.append(' ') catch return 0;
            out.appendSlice(monthNames[@as(usize, @intCast(c.month - 1))]) catch return 0;
            out.append(' ') catch return 0;
            appendFour(&out, c.year) catch return 0;
            out.append(' ') catch return 0;
            appendTwo(&out, c.hour) catch return 0;
            out.append(':') catch return 0;
            appendTwo(&out, c.minute) catch return 0;
            out.append(':') catch return 0;
            appendTwo(&out, c.second) catch return 0;
            out.appendSlice(" GMT") catch return 0;
        },
        else => unreachable,
    }
    const text = out.toOwnedSlice() catch return 0;
    return openOwnedBuffer(text) catch return 0;
}

pub export fn sa_time_set_field(ms: i64, field: u64, value: i64) i64 {
    const c = civilParts(ms);
    var y = c.year;
    var mo = c.month;
    var d = c.day;
    var tod: i64 = c.hour * 3600000 + c.minute * 60000 + c.second * 1000 + c.milli;
    switch (field) {
        0 => y = value,
        1 => {
            const tm = y * 12 + value;
            y = @divFloor(tm, 12);
            mo = @mod(tm, 12) + 1;
        },
        2 => d = value,
        3 => tod = value * 3600000 + @mod(tod, 3600000),
        4 => tod = (tod - @mod(tod, 3600000)) + value * 60000 + @mod(tod, 60000),
        5 => tod = (tod - @mod(tod, 60000)) + value * 1000 + @mod(tod, 1000),
        6 => tod = tod - @mod(tod, 1000) + value,
        else => return ms,
    }
    // Fold months once more (setFullYear keeps mo; setMonth pre-folded).
    const tm = y * 12 + (mo - 1);
    const y2 = @divFloor(tm, 12);
    const m2 = @mod(tm, 12) + 1;
    // Day overflow rolls through the 1st plus offset.
    const days = daysFromCivil(y2, m2, 1) + (d - 1);
    // Time-of-day overflow rolls across days.
    const total_days = days + @divFloor(tod, 86400000);
    const tod_norm = tod - @divFloor(tod, 86400000) * 86400000;
    return (total_days * 86400) * 1000 + tod_norm;
}

pub export fn sa_time_unix_ns() i64 {
    if (!policyAllows(.time)) return 0;
    const ts = std.Io.Clock.real.now(sio.io()).toNanoseconds();
    return std.math.cast(i64, ts) orelse std.math.maxInt(i64);
}

pub export fn sa_time_utc_now(out_date: ?*TimeDate) i32 {
    const ptr = out_date orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (!policyAllows(.time)) return finish(SA_STD_ERR_PERMISSION_DENIED);
    fillUtcNow(ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ns(ns: u64) i32 {
    sio.io().sleep(.fromNanoseconds(@as(i96, @intCast(ns))), .awake) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_time_sleep_ms(ms: u64) i32 {
    const ns = std.math.mul(u64, ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return sa_time_sleep_ns(ns);
}
