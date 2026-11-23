const std = @import("std");
const ERR_INVALID = @import("sa_crypto_asym.zig").ERR_INVALID;
const ERR_NOMEM = @import("sa_crypto_asym.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("sa_crypto_asym.zig").ERR_NOT_FOUND;
const Elem = @import("sa_crypto_asym.zig").Elem;
const OK = @import("sa_crypto_asym.zig").OK;
const Seq = @import("sa_crypto_asym.zig").Seq;
const algOid = @import("sa_crypto_asym.zig").algOid;
const bitStringBytes = @import("sa_crypto_asym.zig").bitStringBytes;
const inSlice = @import("sa_crypto_asym.zig").inSlice;
const oidIs = @import("sa_crypto_asym.zig").oidIs;
const oid_cn = @import("sa_crypto_asym.zig").oid_cn;
const oid_ec_public_key = @import("sa_crypto_asym.zig").oid_ec_public_key;
const oid_ed25519 = @import("sa_crypto_asym.zig").oid_ed25519;
const oid_rsa_encryption = @import("sa_crypto_asym.zig").oid_rsa_encryption;
const oid_rsa_pss = @import("sa_crypto_asym.zig").oid_rsa_pss;
const seqOf = @import("sa_crypto_asym.zig").seqOf;
const topElem = @import("sa_crypto_asym.zig").topElem;
const writeOut = @import("sa_crypto_asym.zig").writeOut;

pub export fn sa_pem_decode(pem_ptr: ?[*]const u8, pem_len: u64, label_ptr: ?[*]const u8, label_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const pem = inSlice(pem_ptr, pem_len) orelse return ERR_INVALID;
    const label = inSlice(label_ptr, label_len) orelse return ERR_INVALID;
    if (label.len == 0) return ERR_INVALID;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const begin = std.fmt.allocPrint(a, "-----BEGIN {s}-----", .{label}) catch return ERR_NOMEM;
    const endmark = std.fmt.allocPrint(a, "-----END {s}-----", .{label}) catch return ERR_NOMEM;
    const bidx = std.mem.indexOf(u8, pem, begin) orelse return ERR_NOT_FOUND;
    const body_start = bidx + begin.len;
    const eidx = std.mem.indexOfPos(u8, pem, body_start, endmark) orelse return ERR_INVALID;
    const body = pem[body_start..eidx];
    // Keep only base64-alphabet lines; this also skips RFC 1421
    // header lines (they contain ':' / ',' / spaces).
    var b64: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0) continue;
        var pure = true;
        for (t) |c| {
            const okc = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '+' or c == '/' or c == '=';
            if (!okc) {
                pure = false;
                break;
            }
        }
        if (pure) b64.appendSlice(a, t) catch return ERR_NOMEM;
    }
    if (b64.items.len == 0) return ERR_INVALID;
    const dec = std.base64.standard.Decoder;
    const need = dec.calcSizeForSlice(b64.items) catch return ERR_INVALID;
    const buf = a.alloc(u8, need) catch return ERR_NOMEM;
    dec.decode(buf, b64.items) catch return ERR_INVALID;
    return writeOut(out_ptr, cap, out_len, buf);
}

pub fn certParts(der: []const u8) error{Invalid}!struct {
    subject: Elem,
    spki: Elem,
    validity: Elem,
} {
    const outer = try topElem(der, 0x30);
    var s = try seqOf(outer);
    const tbs = try s.next();
    var t = try seqOf(tbs);
    if ((try t.peekTag()) == 0xa0) _ = try t.next(); // [0] version
    _ = try t.next(); // serial
    _ = try t.next(); // signature algorithm
    _ = try t.next(); // issuer
    const validity = try t.next();
    const subject = try t.next();
    const spki = try t.next();
    return .{ .subject = subject, .spki = spki, .validity = validity };
}

pub export fn sa_x509_spki(cert_ptr: ?[*]const u8, cert_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const cert = inSlice(cert_ptr, cert_len) orelse return ERR_INVALID;
    const parts = certParts(cert) catch return ERR_INVALID;
    return writeOut(out_ptr, cap, out_len, parts.spki.full);
}

pub export fn sa_x509_subject(cert_ptr: ?[*]const u8, cert_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const cert = inSlice(cert_ptr, cert_len) orelse return ERR_INVALID;
    const parts = certParts(cert) catch return ERR_INVALID;
    return writeOut(out_ptr, cap, out_len, parts.subject.full);
}

pub export fn sa_x509_subject_cn(cert_ptr: ?[*]const u8, cert_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const cert = inSlice(cert_ptr, cert_len) orelse return ERR_INVALID;
    const parts = certParts(cert) catch return ERR_INVALID;
    var rdns = seqOf(parts.subject) catch return ERR_INVALID;
    while (!rdns.done()) {
        const rdn = rdns.next() catch return ERR_INVALID;
        if (rdn.tag != 0x31) return ERR_INVALID;
        var atvs = Seq{ .content = rdn.content };
        while (!atvs.done()) {
            const atv = atvs.next() catch return ERR_INVALID;
            var pair = seqOf(atv) catch return ERR_INVALID;
            const oid = pair.next() catch return ERR_INVALID;
            const val = pair.next() catch return ERR_INVALID;
            if (oidIs(oid, &oid_cn)) {
                // UTF8String / PrintableString / IA5String / T61 are
                // byte-compatible for CN display purposes.
                if (val.tag != 0x0c and val.tag != 0x13 and val.tag != 0x16 and val.tag != 0x14) return ERR_INVALID;
                return writeOut(out_ptr, cap, out_len, val.content);
            }
        }
    }
    const ol = out_len orelse return ERR_INVALID;
    ol.* = 0;
    return ERR_NOT_FOUND;
}

pub export fn sa_x509_public_key(cert_ptr: ?[*]const u8, cert_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64, out_algo: ?*u32) i32 {
    const cert = inSlice(cert_ptr, cert_len) orelse return ERR_INVALID;
    const oa = out_algo orelse return ERR_INVALID;
    // Walk the certificate with this module's own bounds-checked DER
    // reader (the same machinery as the sibling x509 faces).
    // std.crypto.Certificate.parse is not truncation-safe: its
    // element reader indexes the buffer without a bounds check and
    // panics on short or malformed input, which would crash the host
    // on untrusted certificates. Every step here instead fails with
    // error.Invalid, mapped to ERR_INVALID.
    const parts = certParts(cert) catch return ERR_INVALID;
    var s = seqOf(parts.spki) catch return ERR_INVALID;
    const alg = s.next() catch return ERR_INVALID;
    const oid = algOid(alg) catch return ERR_INVALID;
    const bits = s.next() catch return ERR_INVALID;
    const key = bitStringBytes(bits) catch return ERR_INVALID;
    oa.* = if (oidIs(oid, &oid_rsa_encryption))
        1
    else if (oidIs(oid, &oid_ec_public_key))
        2
    else if (oidIs(oid, &oid_ed25519))
        3
    else if (oidIs(oid, &oid_rsa_pss))
        4
    else
        return ERR_INVALID;
    return writeOut(out_ptr, cap, out_len, key);
}

pub fn daysFromCivil(y0: i64, m: u64, d: u64) i64 {
    var y = y0;
    if (m <= 2) y -= 1;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else -@divFloor(-y + 399, 400);
    const yoe: u64 = @intCast(y - era * 400);
    const mp: u64 = if (m > 2) m - 3 else m + 9;
    const doy: u64 = (153 * mp + 2) / 5 + d - 1;
    const doe: u64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + @as(i64, @intCast(doe)) - 719468;
}

pub fn parseUint(b: []const u8) ?u64 {
    var v: u64 = 0;
    for (b) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    return v;
}

pub fn parseDerTime(e: Elem) error{Invalid}!i64 {
    const b = e.content;
    var year: i64 = undefined;
    var rest: []const u8 = undefined;
    if (e.tag == 0x17) {
        if (b.len != 13 or b[12] != 'Z') return error.Invalid;
        const yy = parseUint(b[0..2]) orelse return error.Invalid;
        year = if (yy < 50) 2000 + @as(i64, @intCast(yy)) else 1900 + @as(i64, @intCast(yy));
        rest = b[2..12];
    } else if (e.tag == 0x18) {
        if (b.len != 15 or b[14] != 'Z') return error.Invalid;
        year = @intCast(parseUint(b[0..4]) orelse return error.Invalid);
        rest = b[4..14];
    } else return error.Invalid;
    const mo = parseUint(rest[0..2]) orelse return error.Invalid;
    const dy = parseUint(rest[2..4]) orelse return error.Invalid;
    const hh = parseUint(rest[4..6]) orelse return error.Invalid;
    const mi = parseUint(rest[6..8]) orelse return error.Invalid;
    const ss = parseUint(rest[8..10]) orelse return error.Invalid;
    if (mo < 1 or mo > 12 or dy < 1 or dy > 31 or hh > 23 or mi > 59 or ss > 60) return error.Invalid;
    const days = daysFromCivil(year, mo, dy);
    return days * 86400 + @as(i64, @intCast(hh * 3600 + mi * 60 + ss));
}

pub export fn sa_x509_validity(cert_ptr: ?[*]const u8, cert_len: u64, out_not_before: ?*i64, out_not_after: ?*i64) i32 {
    const cert = inSlice(cert_ptr, cert_len) orelse return ERR_INVALID;
    const nb = out_not_before orelse return ERR_INVALID;
    const na = out_not_after orelse return ERR_INVALID;
    const parts = certParts(cert) catch return ERR_INVALID;
    var v = seqOf(parts.validity) catch return ERR_INVALID;
    const e_nb = v.next() catch return ERR_INVALID;
    const e_na = v.next() catch return ERR_INVALID;
    nb.* = parseDerTime(e_nb) catch return ERR_INVALID;
    na.* = parseDerTime(e_na) catch return ERR_INVALID;
    return OK;
}

pub fn unhex(comptime s: []const u8) [s.len / 2]u8 {
    // The embedded openssl fixtures run to ~800 bytes; the default
    // comptime branch quota (1000) is far below the decode loop cost.
    @setEvalBranchQuota(100_000);
    var out: [s.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, s) catch unreachable;
    return out;
}
