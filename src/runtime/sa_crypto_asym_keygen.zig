const std = @import("std");
const ERR_INVALID = @import("sa_crypto_asym.zig").ERR_INVALID;
const ERR_NOMEM = @import("sa_crypto_asym.zig").ERR_NOMEM;
const ERR_TRUNCATED = @import("sa_crypto_asym.zig").ERR_TRUNCATED;
const Managed = @import("sa_crypto_asym.zig").Managed;
const OK = @import("sa_crypto_asym.zig").OK;
const appendTlv = @import("sa_crypto_asym.zig").appendTlv;
const bigByteLen = @import("sa_crypto_asym.zig").bigByteLen;
const bigFromBytes = @import("sa_crypto_asym.zig").bigFromBytes;
const modExp = @import("sa_crypto_asym.zig").modExp;
const modOf = @import("sa_crypto_asym.zig").modOf;
const mulMod = @import("sa_crypto_asym.zig").mulMod;
const oid_rsa_encryption = @import("sa_crypto_asym.zig").oid_rsa_encryption;
const sio = @import("sa_crypto_asym.zig").sio;

pub fn derIntContent(a: std.mem.Allocator, mag: []const u8) ![]u8 {
    var b = mag;
    while (b.len > 1 and b[0] == 0) b = b[1..];
    const pad: usize = if (b.len > 0 and b[0] & 0x80 != 0) 1 else 0;
    const out = try a.alloc(u8, b.len + pad);
    if (pad == 1) out[0] = 0;
    @memcpy(out[pad..], b);
    return out;
}

pub fn nibbleValue(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

pub fn bigToBytes(a: std.mem.Allocator, v: *const Managed) ![]u8 {
    const nbytes = bigByteLen(v);
    const out = try a.alloc(u8, nbytes);
    if (nbytes == 0) return out;
    @memset(out, 0);
    const hex = try v.toString(a, 16, .lower);
    defer a.free(hex);
    var oi: usize = nbytes;
    var hi: usize = hex.len;
    while (hi > 0) {
        const lo = nibbleValue(hex[hi - 1]);
        const hi_n: u8 = if (hi >= 2) nibbleValue(hex[hi - 2]) else 0;
        oi -= 1;
        out[oi] = (hi_n << 4) | lo;
        if (hi >= 2) {
            hi -= 2;
        } else {
            hi = 0;
        }
    }
    return out;
}

pub const small_primes = [_]u32{
    3,  5,  7,  11, 13, 17, 19, 23, 29, 31,  37,  41,  43,  47,  53,
    59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127,
    131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193,
    197, 199, 211, 223, 227, 229, 233, 239, 241, 251,
};

pub fn modInverse(a: std.mem.Allocator, x: *const Managed, m: *const Managed) !Managed {
    var old_r = try x.clone();
    var r = try m.clone();
    var old_s = try Managed.initSet(a, @as(u32, 1));
    var s = try Managed.initSet(a, @as(u32, 0));
    while (!r.eqlZero()) {
        var q = try Managed.init(a);
        var rem = try Managed.init(a);
        try Managed.divFloor(&q, &rem, &old_r, &r);
        var qs = try Managed.init(a);
        try qs.mul(&q, &s);
        var ns = try Managed.init(a);
        try ns.sub(&old_s, &qs);
        old_s = s;
        s = ns;
        old_r = r;
        r = rem;
    }
    return modOf(a, &old_s, m);
}

pub fn isProbablePrime(a: std.mem.Allocator, n: *const Managed) !bool {
    var two = try Managed.initSet(a, @as(u32, 2));
    _ = &two;
    for (small_primes) |p| {
        var pm = try Managed.initSet(a, p);
        var q = try Managed.init(a);
        var r = try Managed.init(a);
        try Managed.divFloor(&q, &r, n, &pm);
        if (r.eqlZero()) {
            var nv = try n.clone();
            return nv.eql(pm);
        }
    }
    // n - 1 = 2^s * d with d odd.
    var one = try Managed.initSet(a, @as(u32, 1));
    var nm1 = try Managed.init(a);
    try nm1.sub(n, &one);
    var d = try nm1.clone();
    var s: usize = 0;
    while (d.isEven()) {
        var nd = try Managed.init(a);
        try nd.shiftRight(&d, 1);
        d = nd;
        s += 1;
    }
    const d_bytes = try bigToBytes(a, &d);
    const nbytes = bigByteLen(n);
    const draw = try a.alloc(u8, nbytes);
    var nm3 = try Managed.init(a);
    var three = try Managed.initSet(a, @as(u32, 3));
    _ = &three;
    try nm3.sub(n, &three);
    var rounds: usize = 0;
    while (rounds < 12) : (rounds += 1) {
        sio.io().random(draw);
        const draw_big = try bigFromBytes(a, draw);
        var base = try modOf(a, &draw_big, &nm3);
        try base.add(&base, &two);
        var x = try modExp(a, &base, d_bytes, n);
        if (x.eql(one) or x.eql(nm1)) continue;
        var passed = false;
        var i: usize = 1;
        while (i < s) : (i += 1) {
            x = try mulMod(a, &x, &x, n);
            if (x.eql(nm1)) {
                passed = true;
                break;
            }
        }
        if (!passed) return false;
    }
    return true;
}

pub fn genPrime(a: std.mem.Allocator, half_bits: usize) !Managed {
    const nbytes = half_bits / 8;
    const buf = try a.alloc(u8, nbytes);
    while (true) {
        sio.io().random(buf);
        buf[0] |= 0xc0;
        buf[nbytes - 1] |= 1;
        const cand = try bigFromBytes(a, buf);
        if (try isProbablePrime(a, &cand)) return cand;
    }
}

pub const GeneratedKeypair = struct { spki: []u8, pkcs8: []u8 };

pub fn derInt(a: std.mem.Allocator, mag: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try appendTlv(&out, a, 0x02, try derIntContent(a, mag));
    return out.items;
}

pub fn derSeq(a: std.mem.Allocator, content: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try appendTlv(&out, a, 0x30, content);
    return out.items;
}

pub fn rsaAlgIdSeq(a: std.mem.Allocator) ![]u8 {
    var alg: std.ArrayList(u8) = .empty;
    try appendTlv(&alg, a, 0x06, &oid_rsa_encryption);
    try appendTlv(&alg, a, 0x05, &.{});
    return derSeq(a, alg.items);
}

pub fn generateRsaKeypair(a: std.mem.Allocator, bits: u32) !GeneratedKeypair {
    const half: usize = @intCast(bits / 2);
    var e = try Managed.initSet(a, @as(u32, 65537));
    var one = try Managed.initSet(a, @as(u32, 1));
    while (true) {
        const p = try genPrime(a, half);
        const q = try genPrime(a, @as(usize, @intCast(bits)) - half);
        if (p.eql(q)) continue;
        var n = try Managed.init(a);
        try n.mul(&p, &q);
        if (n.bitCountAbs() != @as(usize, @intCast(bits))) continue;
        var pm1 = try Managed.init(a);
        try pm1.sub(&p, &one);
        var qm1 = try Managed.init(a);
        try qm1.sub(&q, &one);
        var g = try Managed.init(a);
        try Managed.gcd(&g, &pm1, &qm1);
        var lam_quot = try Managed.init(a);
        var lam_rem = try Managed.init(a);
        try Managed.divFloor(&lam_quot, &lam_rem, &pm1, &g);
        var lam = try Managed.init(a);
        try lam.mul(&lam_quot, &qm1);
        var ge = try Managed.init(a);
        try Managed.gcd(&ge, &e, &lam);
        if (!ge.eql(one)) continue;
        const d = try modInverse(a, &e, &lam);
        var dp = try modOf(a, &d, &pm1);
        var dq = try modOf(a, &d, &qm1);
        const qinv = try modInverse(a, &q, &p);

        const n_b = try bigToBytes(a, &n);
        const e_b = try bigToBytes(a, &e);
        const d_b = try bigToBytes(a, &d);
        const p_b = try bigToBytes(a, &p);
        const q_b = try bigToBytes(a, &q);
        const dp_b = try bigToBytes(a, &dp);
        const dq_b = try bigToBytes(a, &dq);
        const qinv_b = try bigToBytes(a, &qinv);
        const ver_tlv = try derInt(a, &.{0});

        // PKCS#1 RSAPrivateKey ::= SEQ { 0, n, e, d, p, q, dp, dq, qinv }
        var priv_body: std.ArrayList(u8) = .empty;
        try priv_body.appendSlice(a, ver_tlv);
        for ([_][]const u8{ n_b, e_b, d_b, p_b, q_b, dp_b, dq_b, qinv_b }) |part| {
            try priv_body.appendSlice(a, try derInt(a, part));
        }
        const pkcs1 = try derSeq(a, priv_body.items);

        const alg_seq = try rsaAlgIdSeq(a);

        // PKCS#8 PrivateKeyInfo ::= SEQ { 0, algId, OCTET STRING(pkcs1) }
        var p8_body: std.ArrayList(u8) = .empty;
        try p8_body.appendSlice(a, ver_tlv);
        try p8_body.appendSlice(a, alg_seq);
        try appendTlv(&p8_body, a, 0x04, pkcs1);
        const pkcs8 = try derSeq(a, p8_body.items);

        // SPKI ::= SEQ { algId, BIT STRING(0x00 || SEQ { n, e }) }
        var pub_body: std.ArrayList(u8) = .empty;
        try pub_body.appendSlice(a, try derInt(a, n_b));
        try pub_body.appendSlice(a, try derInt(a, e_b));
        const pkcs1_pub = try derSeq(a, pub_body.items);
        var bits_content = try a.alloc(u8, pkcs1_pub.len + 1);
        bits_content[0] = 0;
        @memcpy(bits_content[1..], pkcs1_pub);
        var spki_body: std.ArrayList(u8) = .empty;
        try spki_body.appendSlice(a, alg_seq);
        try appendTlv(&spki_body, a, 0x03, bits_content);
        const spki = try derSeq(a, spki_body.items);

        return .{ .spki = spki, .pkcs8 = pkcs8 };
    }
}

pub export fn sa_rsa_generate_keypair(bits: u32, pub_ptr: ?[*]u8, pub_cap: u64, pub_len: ?*u64, priv_ptr: ?[*]u8, priv_cap: u64, priv_len: ?*u64) i32 {
    const pl = pub_len orelse return ERR_INVALID;
    const ql = priv_len orelse return ERR_INVALID;
    pl.* = 0;
    ql.* = 0;
    if (bits < 1024 or bits > 4096 or bits % 2 != 0) return ERR_INVALID;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const kp = generateRsaKeypair(a, bits) catch return ERR_NOMEM;
    pl.* = @intCast(kp.spki.len);
    ql.* = @intCast(kp.pkcs8.len);
    if (kp.spki.len > pub_cap or kp.pkcs8.len > priv_cap) return ERR_TRUNCATED;
    const po = pub_ptr orelse return ERR_INVALID;
    const qo = priv_ptr orelse return ERR_INVALID;
    @memcpy(po[0..kp.spki.len], kp.spki);
    @memcpy(qo[0..kp.pkcs8.len], kp.pkcs8);
    return OK;
}
