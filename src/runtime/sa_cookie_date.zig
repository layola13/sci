const std = @import("std");
const eqFold = @import("sa_cookie.zig").eqFold;
const sa_cookie_set_expires = @import("sa_cookie.zig").sa_cookie_set_expires;

pub fn daysFromCivil(y0: i64, m: u32, d: u32) i64 {
    var y = y0;
    if (m <= 2) y -= 1;
    const era: i64 = @divFloor(y, 400);
    const yoe: u64 = @intCast(y - era * 400);
    const mp: u64 = if (m > 2) m - 3 else m + 9;
    const doy: u64 = (153 * mp + 2) / 5 + @as(u64, d) - 1;
    const doe: u64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + @as(i64, @intCast(doe)) - 719468;
}

pub const Civil = struct { year: i64, month: u32, day: u32 };

pub fn civilFromDays(z0: i64) Civil {
    const z = z0 + 719468;
    const era: i64 = @divFloor(z, 146097);
    const doe: u64 = @intCast(z - era * 146097);
    const yoe: u64 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const y: i64 = @as(i64, @intCast(yoe)) + era * 400;
    const doy: u64 = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp: u64 = (5 * doy + 2) / 153;
    const d: u32 = @intCast(doy - (153 * mp + 2) / 5 + 1);
    const m: u32 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{ .year = if (m <= 2) y + 1 else y, .month = m, .day = d };
}

pub fn isDateDelimiter(c: u8) bool {
    // RFC 6265 5.1.1 delimiter set.
    return c == 0x09 or (c >= 0x20 and c <= 0x2f) or (c >= 0x3b and c <= 0x40) or
        (c >= 0x5b and c <= 0x60) or (c >= 0x7b and c <= 0x7e);
}

pub const month_names = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };

pub fn parseLeadingUint(token: []const u8, max_digits: usize) ?struct { value: u32, digits: usize } {
    var value: u32 = 0;
    var n: usize = 0;
    while (n < token.len and n < max_digits and std.ascii.isDigit(token[n])) : (n += 1) {
        value = value * 10 + @as(u32, token[n] - '0');
    }
    if (n == 0) return null;
    return .{ .value = value, .digits = n };
}

pub const TimeOfDay = struct { h: u32, m: u32, s: u32 };

pub fn tokenTime(token: []const u8) ?TimeOfDay {
    // hms-time: 1*2DIGIT ":" 1*2DIGIT ":" 1*2DIGIT, trailing junk ignored.
    const h = parseLeadingUint(token, 2) orelse return null;
    var rest = token[h.digits..];
    if (rest.len == 0 or rest[0] != ':') return null;
    rest = rest[1..];
    const m = parseLeadingUint(rest, 2) orelse return null;
    rest = rest[m.digits..];
    if (rest.len == 0 or rest[0] != ':') return null;
    rest = rest[1..];
    const s = parseLeadingUint(rest, 2) orelse return null;
    return .{ .h = h.value, .m = m.value, .s = s.value };
}

pub fn parseCookieDate(s: []const u8) ?i64 {
    var time: ?TimeOfDay = null;
    var day: ?u32 = null;
    var month: ?u32 = null;
    var year: ?i64 = null;

    var i: usize = 0;
    while (i < s.len) {
        while (i < s.len and isDateDelimiter(s[i])) i += 1;
        if (i >= s.len) break;
        const start = i;
        while (i < s.len and !isDateDelimiter(s[i])) i += 1;
        const token = s[start..i];

        if (time == null) {
            if (tokenTime(token)) |t| {
                time = t;
                continue;
            }
        }
        if (day == null) {
            if (parseLeadingUint(token, 2)) |d| {
                // A day token is 1-2 digits not followed by another digit.
                if (d.digits == token.len or !std.ascii.isDigit(token[d.digits])) {
                    day = d.value;
                    continue;
                }
            }
        }
        if (month == null and token.len >= 3) {
            var matched: ?u32 = null;
            for (month_names, 0..) |name, idx| {
                if (eqFold(token[0..3], name)) {
                    matched = @intCast(idx + 1);
                    break;
                }
            }
            if (matched) |mo| {
                month = mo;
                continue;
            }
        }
        if (year == null) {
            if (parseLeadingUint(token, 4)) |y| {
                if (y.digits >= 2 and (y.digits == token.len or !std.ascii.isDigit(token[y.digits]))) {
                    var v: i64 = @intCast(y.value);
                    if (y.digits == 2) {
                        if (v >= 70) {
                            v += 1900;
                        } else {
                            v += 2000;
                        }
                    }
                    year = v;
                    continue;
                }
            }
        }
    }

    const t = time orelse return null;
    const d = day orelse return null;
    const mo = month orelse return null;
    const y = year orelse return null;
    if (d < 1 or d > 31) return null;
    if (y < 1601) return null;
    if (t.h > 23 or t.m > 59 or t.s > 59) return null;
    const days = daysFromCivil(y, mo, d);
    return days * 86400 + @as(i64, t.h) * 3600 + @as(i64, t.m) * 60 + @as(i64, t.s);
}

pub const weekday_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

pub const month_names_full = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub fn formatImfFixdate(unix: i64, buf: *[40]u8) []const u8 {
    const days = @divFloor(unix, 86400);
    var rem = unix - days * 86400;
    const c = civilFromDays(days);
    const wd: usize = @intCast(@mod(days + 4, 7));
    const hh: u32 = @intCast(@divFloor(rem, 3600));
    rem -= @as(i64, hh) * 3600;
    const mm: u32 = @intCast(@divFloor(rem, 60));
    const ss: u32 = @intCast(rem - @as(i64, mm) * 60);
    // The year goes through an unsigned format on the common path:
    // Zig pads signed integers with an explicit '+' ("+1994"),
    // which is not IMF-fixdate. Out-of-range years (reachable only
    // through sa_cookie_set_expires with an extreme value) fall
    // back to an unpadded rendering.
    if (c.year >= 0 and c.year <= 9999) {
        return std.fmt.bufPrint(buf, "{s}, {d:0>2} {s} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
            weekday_names[wd], c.day, month_names_full[c.month - 1], @as(u64, @intCast(c.year)), hh, mm, ss,
        }) catch buf[0..0];
    }
    return std.fmt.bufPrint(buf, "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
        weekday_names[wd], c.day, month_names_full[c.month - 1], c.year, hh, mm, ss,
    }) catch buf[0..0];
}
