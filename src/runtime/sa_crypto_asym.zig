//! sa_std asymmetric crypto (STD batch 4, 2026-10-28): RSA
//! (PKCS#1 v1.5 sign/verify, OAEP-SHA256 decrypt, JWK import),
//! DER key import for Ed25519 / ECDSA P-256, a minimal x509
//! certificate reader, and PEM decoding. Driven by the sub2api /
//! new-api census: RS256 JWT verification, payment signature
//! checks, OIDC JWKS and WebAuthn all had no sa_std data surface.
//!
//! Zig std.crypto has no RSA, so RSA here is schoolbook modexp
//! over std.math.big.int with EMSA-PKCS1-v1_5 encoding; the
//! private-key operation is plain (no CRT) -- correct, and fast
//! enough for verification-shaped workloads (the public exponent
//! path is a handful of multiplications); signing a 4096-bit key
//! takes the full square-and-multiply over the private exponent.
//! Keys cross the boundary as DER (SPKI / PKCS#1 / PKCS#8), never
//! as handles: parsing happens per call and no key material is
//! retained by the runtime. Status conventions match
//! sa_crypto.zig: 0 ok, 1 invalid, 3 not found, 4 access
//! (OAEP decryption failure -- one code for every failure, so the
//! API does not become a padding oracle), 5 nomem, 9 truncated.
//! Verification returns OK with out_valid = 0 on a mere mismatch.

test "sa_crypto_asym_tests" { std.testing.refAllDecls(@import("sa_crypto_asym_test.zig")); }

const std = @import("std");
pub const sio = @import("sio");

pub const OK: i32 = 0;
pub const ERR_INVALID: i32 = 1;
pub const ERR_NOT_FOUND: i32 = 3;
pub const ERR_ACCESS: i32 = 4;
pub const ERR_NOMEM: i32 = 5;
pub const ERR_TRUNCATED: i32 = 9;

pub fn inSlice(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return &.{};
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

pub fn writeOut(out_ptr: ?[*]u8, cap: u64, out_len: ?*u64, data: []const u8) i32 {
    const ol = out_len orelse return ERR_INVALID;
    ol.* = @intCast(data.len);
    if (data.len > cap) return ERR_TRUNCATED;
    const o = out_ptr orelse return ERR_INVALID;
    @memcpy(o[0..data.len], data);
    return OK;
}

// ---------------- minimal DER reader ----------------
//
// Just enough ASN.1 DER for SPKI / PKCS#1 / PKCS#8 / X.509:
// single-byte tags, definite lengths (short form and up to two
// long-form bytes), no indefinite form (illegal in DER anyway).

pub const Elem = struct {
    tag: u8,
    content: []const u8,
    full: []const u8,
};

pub fn readElem(bytes: []const u8, pos: *usize) error{Invalid}!Elem {
    if (pos.* + 2 > bytes.len) return error.Invalid;
    const start = pos.*;
    const tag = bytes[pos.*];
    var p = start + 1;
    const lb = bytes[p];
    p += 1;
    var len: usize = undefined;
    if (lb & 0x80 == 0) {
        len = lb;
    } else {
        const n: usize = lb & 0x7f;
        if (n == 0 or n > 2) return error.Invalid;
        if (p + n > bytes.len) return error.Invalid;
        len = 0;
        for (0..n) |i| len = (len << 8) | bytes[p + i];
        p += n;
    }
    if (p + len > bytes.len) return error.Invalid;
    pos.* = p + len;
    return .{ .tag = tag, .content = bytes[p .. p + len], .full = bytes[start .. p + len] };
}

/// Parses `bytes` as exactly one element of the given tag spanning
/// the whole input.
pub fn topElem(bytes: []const u8, tag: u8) error{Invalid}!Elem {
    var pos: usize = 0;
    const e = try readElem(bytes, &pos);
    if (e.tag != tag or pos != bytes.len) return error.Invalid;
    return e;
}

/// A cursor over the children of a SEQUENCE's content.
pub const Seq = struct {
    content: []const u8,
    pos: usize = 0,

    pub fn next(self: *Seq) error{Invalid}!Elem {
        if (self.pos >= self.content.len) return error.Invalid;
        return readElem(self.content, &self.pos);
    }
    pub fn peekTag(self: *const Seq) error{Invalid}!u8 {
        if (self.pos >= self.content.len) return error.Invalid;
        return self.content[self.pos];
    }
    pub fn done(self: *const Seq) bool {
        return self.pos >= self.content.len;
    }
};

pub fn seqOf(e: Elem) error{Invalid}!Seq {
    if (e.tag != 0x30) return error.Invalid;
    return .{ .content = e.content };
}

/// DER INTEGER content as unsigned magnitude bytes (leading zero
/// bytes stripped). A negative INTEGER is invalid for key material.
fn intMagnitude(e: Elem) error{Invalid}![]const u8 {
    if (e.tag != 0x02 or e.content.len == 0) return error.Invalid;
    var b = e.content;
    if (b[0] & 0x80 != 0) return error.Invalid; // negative
    while (b.len > 1 and b[0] == 0) b = b[1..];
    return b;
}

pub const oid_rsa_encryption = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01 };
pub const oid_ec_public_key = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 };
const oid_p256 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };
pub const oid_ed25519 = [_]u8{ 0x2b, 0x65, 0x70 };
pub const oid_rsa_pss = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0a };
pub const oid_cn = [_]u8{ 0x55, 0x04, 0x03 };

pub fn oidIs(e: Elem, oid: []const u8) bool {
    return e.tag == 0x06 and std.mem.eql(u8, e.content, oid);
}

/// Parses an AlgorithmIdentifier SEQUENCE and returns its OID
/// element; parameters (if any) are left unread.
pub fn algOid(alg_seq: Elem) error{Invalid}!Elem {
    var s = try seqOf(alg_seq);
    const oid = try s.next();
    if (oid.tag != 0x06) return error.Invalid;
    return oid;
}

/// BIT STRING content octets (the leading unused-bits byte must
/// be zero for key material).
pub fn bitStringBytes(e: Elem) error{Invalid}![]const u8 {
    if (e.tag != 0x03 or e.content.len == 0) return error.Invalid;
    if (e.content[0] != 0) return error.Invalid;
    return e.content[1..];
}

// ---------------- RSA ----------------

const RsaPub = struct { n: []const u8, e: []const u8 };
const RsaPriv = struct { n: []const u8, d: []const u8 };

/// Accepts SPKI (SubjectPublicKeyInfo) or a bare PKCS#1
/// RSAPublicKey, auto-detected by the first child's tag.
pub fn parseRsaPublic(der: []const u8) error{Invalid}!RsaPub {
    const outer = try topElem(der, 0x30);
    var s = try seqOf(outer);
    const first_tag = try s.peekTag();
    if (first_tag == 0x30) {
        // SPKI: AlgorithmIdentifier, then BIT STRING wrapping PKCS#1.
        const alg = try s.next();
        if (!oidIs(try algOid(alg), &oid_rsa_encryption)) return error.Invalid;
        const bits = try s.next();
        const pkcs1 = try bitStringBytes(bits);
        return parseRsaPublic(pkcs1);
    }
    // PKCS#1 RSAPublicKey ::= SEQUENCE { n INTEGER, e INTEGER }
    const n_e = try s.next();
    const e_e = try s.next();
    return .{ .n = try intMagnitude(n_e), .e = try intMagnitude(e_e) };
}

/// Accepts PKCS#8 PrivateKeyInfo or a bare PKCS#1 RSAPrivateKey,
/// auto-detected by the second child's tag.
pub fn parseRsaPrivate(der: []const u8) error{Invalid}!RsaPriv {
    const outer = try topElem(der, 0x30);
    var s = try seqOf(outer);
    _ = try s.next(); // version INTEGER in both shapes
    const second_tag = try s.peekTag();
    if (second_tag == 0x30) {
        // PKCS#8: AlgorithmIdentifier, then OCTET STRING wrapping PKCS#1.
        const alg = try s.next();
        if (!oidIs(try algOid(alg), &oid_rsa_encryption)) return error.Invalid;
        const oct = try s.next();
        if (oct.tag != 0x04) return error.Invalid;
        return parseRsaPrivate(oct.content);
    }
    // PKCS#1 RSAPrivateKey ::= SEQUENCE { v, n, e, d, ... }
    const n_e = try s.next();
    _ = try s.next(); // e, not needed for the private operation
    const d_e = try s.next();
    return .{ .n = try intMagnitude(n_e), .d = try intMagnitude(d_e) };
}

pub const Managed = std.math.big.int.Managed;

pub fn bigFromBytes(a: std.mem.Allocator, bytes: []const u8) !Managed {
    var b = bytes;
    while (b.len > 1 and b[0] == 0) b = b[1..];
    if (b.len == 0 or (b.len == 1 and b[0] == 0)) return Managed.initSet(a, @as(u32, 0));
    const hexbuf = try a.alloc(u8, b.len * 2);
    defer a.free(hexbuf);
    const hexd = "0123456789abcdef";
    for (b, 0..) |byte, i| {
        hexbuf[2 * i] = hexd[byte >> 4];
        hexbuf[2 * i + 1] = hexd[byte & 0x0f];
    }
    var v = try Managed.init(a);
    errdefer v.deinit();
    try v.setString(16, hexbuf);
    return v;
}

pub fn bigByteLen(v: *const Managed) usize {
    return (v.bitCountAbs() + 7) / 8;
}

pub fn modOf(a: std.mem.Allocator, x: *const Managed, n: *const Managed) !Managed {
    var q = try Managed.init(a);
    defer q.deinit();
    var r = try Managed.init(a);
    errdefer r.deinit();
    try Managed.divFloor(&q, &r, x, n);
    return r;
}

pub fn mulMod(a: std.mem.Allocator, x: *const Managed, y: *const Managed, n: *const Managed) !Managed {
    var t = try Managed.init(a);
    defer t.deinit();
    try t.mul(x, y);
    return modOf(a, &t, n);
}

/// base^exp mod n, exp as big-endian bytes, left-to-right
/// square-and-multiply. All allocations come from the caller's
/// arena, so intermediate values are intentionally not freed.
pub fn modExp(a: std.mem.Allocator, base: *const Managed, exp_bytes: []const u8, n: *const Managed) !Managed {
    // Callers guarantee n is a real RSA modulus (hundreds of bits);
    // result starts at 1 and the first mulMod reduces it.
    var result = try Managed.initSet(a, @as(u32, 1));
    const b = try modOf(a, base, n);
    var exp = exp_bytes;
    while (exp.len > 0 and exp[0] == 0) exp = exp[1..];
    for (exp) |byte| {
        var i: u3 = 7;
        while (true) {
            result = try mulMod(a, &result, &result, n);
            if ((byte >> i) & 1 == 1) result = try mulMod(a, &result, &b, n);
            if (i == 0) break;
            i -= 1;
        }
    }
    return result;
}

const HashAlg = struct {
    digest_len: usize,
    prefix: []const u8,
};

fn hashAlg(id: u32) ?HashAlg {
    return switch (id) {
        0 => .{ .digest_len = 32, .prefix = &[_]u8{ 0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20 } },
        1 => .{ .digest_len = 48, .prefix = &[_]u8{ 0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30 } },
        2 => .{ .digest_len = 64, .prefix = &[_]u8{ 0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40 } },
        else => null,
    };
}

/// Builds the EMSA-PKCS1-v1_5 encoded message for a digest into
/// `em` (k bytes). Caller guarantees k >= prefix+digest+11.
fn emsaEncode(em: []u8, alg: HashAlg, digest: []const u8) void {
    const k = em.len;
    const t_len = alg.prefix.len + digest.len;
    em[0] = 0x00;
    em[1] = 0x01;
    @memset(em[2 .. k - t_len - 1], 0xff);
    em[k - t_len - 1] = 0x00;
    @memcpy(em[k - t_len ..][0..alg.prefix.len], alg.prefix);
    @memcpy(em[k - digest.len ..][0..digest.len], digest);
}

pub export fn sa_rsa_pkcs1_verify(key_ptr: ?[*]const u8, key_len: u64, hash_alg: u32, digest_ptr: ?[*]const u8, digest_len: u64, sig_ptr: ?[*]const u8, sig_len: u64, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const digest = inSlice(digest_ptr, digest_len) orelse return ERR_INVALID;
    const sig = inSlice(sig_ptr, sig_len) orelse return ERR_INVALID;
    const alg = hashAlg(hash_alg) orelse return ERR_INVALID;
    if (digest.len != alg.digest_len) return ERR_INVALID;
    const pubk = parseRsaPublic(key) catch return ERR_INVALID;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = bigFromBytes(a, pubk.n) catch return ERR_NOMEM;
    const k = bigByteLen(&n);
    if (k < alg.prefix.len + alg.digest_len + 11 or k > 512) return ERR_INVALID;
    if (sig.len != k) return OK; // wrong-length signature: invalid, not an error
    const s = bigFromBytes(a, sig) catch return ERR_NOMEM;
    if (s.order(n) != .lt) return OK; // representative out of range
    const m = modExp(a, &s, pubk.e, &n) catch return ERR_NOMEM;
    var em: [512]u8 = undefined;
    m.toConst().writeTwosComplement(em[0..k], .big);
    var expect: [512]u8 = undefined;
    emsaEncode(expect[0..k], alg, digest);
    var diff: u8 = 0;
    for (em[0..k], expect[0..k]) |x, y| diff |= x ^ y;
    ov.* = if (diff == 0) 1 else 0;
    return OK;
}

pub export fn sa_rsa_pkcs1_sign(key_ptr: ?[*]const u8, key_len: u64, hash_alg: u32, digest_ptr: ?[*]const u8, digest_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const digest = inSlice(digest_ptr, digest_len) orelse return ERR_INVALID;
    const alg = hashAlg(hash_alg) orelse return ERR_INVALID;
    if (digest.len != alg.digest_len) return ERR_INVALID;
    const priv = parseRsaPrivate(key) catch return ERR_INVALID;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = bigFromBytes(a, priv.n) catch return ERR_NOMEM;
    const k = bigByteLen(&n);
    if (k < alg.prefix.len + alg.digest_len + 11 or k > 512) return ERR_INVALID;
    var em: [512]u8 = undefined;
    emsaEncode(em[0..k], alg, digest);
    const m = bigFromBytes(a, em[0..k]) catch return ERR_NOMEM;
    const s = modExp(a, &m, priv.d, &n) catch return ERR_NOMEM;
    var sig: [512]u8 = undefined;
    s.toConst().writeTwosComplement(sig[0..k], .big);
    return writeOut(out_ptr, cap, out_len, sig[0..k]);
}

// ---- RSA OAEP with SHA-256 / MGF1-SHA256 ----

fn mgf1Sha256(a: std.mem.Allocator, seed: []const u8, out: []u8) !void {
    var counter: u32 = 0;
    var done: usize = 0;
    while (done < out.len) {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(seed);
        var cbe: [4]u8 = undefined;
        std.mem.writeInt(u32, &cbe, counter, .big);
        h.update(&cbe);
        var block: [32]u8 = undefined;
        h.final(&block);
        const take = @min(32, out.len - done);
        @memcpy(out[done..][0..take], block[0..take]);
        done += take;
        counter += 1;
    }
    _ = a;
}

pub export fn sa_rsa_oaep_sha256_decrypt(key_ptr: ?[*]const u8, key_len: u64, label_ptr: ?[*]const u8, label_len: u64, ct_ptr: ?[*]const u8, ct_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const ol = out_len orelse return ERR_INVALID;
    ol.* = 0;
    const key = inSlice(key_ptr, key_len) orelse return ERR_INVALID;
    const label = inSlice(label_ptr, label_len) orelse return ERR_INVALID;
    const ct = inSlice(ct_ptr, ct_len) orelse return ERR_INVALID;
    const priv = parseRsaPrivate(key) catch return ERR_INVALID;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = bigFromBytes(a, priv.n) catch return ERR_NOMEM;
    const k = bigByteLen(&n);
    // Every failure past this point reports the same status (4):
    // the API must not distinguish padding errors (Bleichenbacher).
    if (ct.len != k or k < 2 * 32 + 2 or k > 512) return ERR_ACCESS;
    const c = bigFromBytes(a, ct) catch return ERR_NOMEM;
    if (c.order(n) != .lt) return ERR_ACCESS;
    const m = modExp(a, &c, priv.d, &n) catch return ERR_NOMEM;
    var em: [512]u8 = undefined;
    m.toConst().writeTwosComplement(em[0..k], .big);
    const emv = em[0..k];
    if (emv[0] != 0) return ERR_ACCESS;
    const masked_seed = emv[1..33];
    const masked_db = emv[33..];
    const db = a.alloc(u8, masked_db.len) catch return ERR_NOMEM;
    const seed_mask = a.alloc(u8, 32) catch return ERR_NOMEM;
    mgf1Sha256(a, masked_db, seed_mask) catch return ERR_NOMEM;
    var seed: [32]u8 = undefined;
    for (masked_seed, seed_mask, 0..) |x, y, i| seed[i] = x ^ y;
    const db_mask = a.alloc(u8, db.len) catch return ERR_NOMEM;
    mgf1Sha256(a, &seed, db_mask) catch return ERR_NOMEM;
    for (masked_db, db_mask, 0..) |x, y, i| db[i] = x ^ y;
    var lhash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(label, &lhash, .{});
    var bad: u8 = 0;
    for (db[0..32], &lhash) |x, y| bad |= x ^ y;
    // Scan the PS region: zeros up to a single 0x01 separator;
    // bytes after the separator are the message, unconstrained.
    var sep: usize = db.len;
    var seen_sep = false;
    for (db[32..], 32..) |byte, idx| {
        if (!seen_sep) {
            if (byte == 0x01) {
                sep = idx;
                seen_sep = true;
            } else if (byte != 0) bad |= 1;
        }
    }
    if (!seen_sep) bad |= 1;
    if (bad != 0) return ERR_ACCESS;
    return writeOut(out_ptr, cap, out_len, db[sep + 1 ..]);
}

// ---- JWK (n / e) -> SPKI DER ----

fn derLenBytes(len: usize, out: *[3]u8) []const u8 {
    if (len < 128) {
        out[0] = @intCast(len);
        return out[0..1];
    } else if (len < 256) {
        out[0] = 0x81;
        out[1] = @intCast(len);
        return out[0..2];
    } else {
        out[0] = 0x82;
        out[1] = @intCast(len >> 8);
        out[2] = @intCast(len & 0xff);
        return out[0..3];
    }
}

pub fn appendTlv(list: *std.ArrayList(u8), a: std.mem.Allocator, tag: u8, content: []const u8) !void {
    try list.append(a, tag);
    var lb: [3]u8 = undefined;
    try list.appendSlice(a, derLenBytes(content.len, &lb));
    try list.appendSlice(a, content);
}

/// DER INTEGER content for an unsigned magnitude (sign pad added
/// when the top bit is set, leading zeros stripped).
pub const derIntContent = @import("sa_crypto_asym_keygen.zig").derIntContent;

pub export fn sa_rsa_jwk_to_spki(n_ptr: ?[*]const u8, n_len: u64, e_ptr: ?[*]const u8, e_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const n_b64 = inSlice(n_ptr, n_len) orelse return ERR_INVALID;
    const e_b64 = inSlice(e_ptr, e_len) orelse return ERR_INVALID;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const dec = std.base64.url_safe_no_pad.Decoder;
    const n_sz = dec.calcSizeForSlice(n_b64) catch return ERR_INVALID;
    const e_sz = dec.calcSizeForSlice(e_b64) catch return ERR_INVALID;
    const n_raw = a.alloc(u8, n_sz) catch return ERR_NOMEM;
    const e_raw = a.alloc(u8, e_sz) catch return ERR_NOMEM;
    dec.decode(n_raw, n_b64) catch return ERR_INVALID;
    dec.decode(e_raw, e_b64) catch return ERR_INVALID;
    const n_bytes = n_raw;
    const e_bytes = e_raw;
    if (n_bytes.len == 0 or e_bytes.len == 0) return ERR_INVALID;

    var pkcs1: std.ArrayList(u8) = .empty;
    var inner: std.ArrayList(u8) = .empty;
    appendTlv(&inner, a, 0x02, derIntContent(a, n_bytes) catch return ERR_NOMEM) catch return ERR_NOMEM;
    appendTlv(&inner, a, 0x02, derIntContent(a, e_bytes) catch return ERR_NOMEM) catch return ERR_NOMEM;
    appendTlv(&pkcs1, a, 0x30, inner.items) catch return ERR_NOMEM;

    var alg: std.ArrayList(u8) = .empty;
    appendTlv(&alg, a, 0x06, &oid_rsa_encryption) catch return ERR_NOMEM;
    appendTlv(&alg, a, 0x05, &.{}) catch return ERR_NOMEM;
    var alg_seq: std.ArrayList(u8) = .empty;
    appendTlv(&alg_seq, a, 0x30, alg.items) catch return ERR_NOMEM;

    var spki_body: std.ArrayList(u8) = .empty;
    spki_body.appendSlice(a, alg_seq.items) catch return ERR_NOMEM;
    const bits = a.alloc(u8, pkcs1.items.len + 1) catch return ERR_NOMEM;
    bits[0] = 0;
    @memcpy(bits[1..], pkcs1.items);
    appendTlv(&spki_body, a, 0x03, bits) catch return ERR_NOMEM;
    var spki: std.ArrayList(u8) = .empty;
    appendTlv(&spki, a, 0x30, spki_body.items) catch return ERR_NOMEM;
    return writeOut(out_ptr, cap, out_len, spki.items);
}

// ---------------- RSA keypair generation / SPKI -> JWK ----------------
//
// GAP-18 (duck2sla line): the RSA face could import, sign, verify
// and OAEP-decrypt, but nothing could MINT a keypair, so callers
// needing a per-request RSA-OAEP JWK (the durableStream block)
// had no honest source for e/n. Generation is schoolbook, like
// the rest of this module: Miller-Rabin prime search over
// std.math.big.int (trial division by the primes < 256, then 12
// random-base rounds; a composite surviving both is negligible),
// e = 65537, d computed modulo lcm(p-1, q-1). Keys leave in the
// same DER shapes the rest of the face consumes -- SPKI for the
// public half, PKCS#8 wrapping a full PKCS#1 (with CRT fields)
// for the private half -- so a generated pair drops straight
// into sa_rsa_pkcs1_sign / sa_rsa_pkcs1_verify /
// sa_rsa_oaep_sha256_decrypt with no handle layer. bits must be
// even and within [1024, 4096]; anything else is status 1, in
// line with the module's modulus ceiling. Output handling
// follows writeOut's convention, extended to two buffers: both
// out_lens are always set to the needed sizes first, status 9
// is returned when either cap is too small, and nothing is
// written in that case.
//
// sa_rsa_spki_to_jwk is the exact inverse of sa_rsa_jwk_to_spki:
// it renders {"kty":"RSA","n":...,"e":...} (base64url, no
// padding) from an SPKI or bare PKCS#1 public key, so a generated
// (or imported) public key can be published as a JWK.

pub const nibbleValue = @import("sa_crypto_asym_keygen.zig").nibbleValue;

/// Big-endian magnitude bytes of a non-negative Managed (the
/// inverse of bigFromBytes).
pub const bigToBytes = @import("sa_crypto_asym_keygen.zig").bigToBytes;

pub const small_primes = @import("sa_crypto_asym_keygen.zig").small_primes;

/// x^{-1} mod m for gcd(x, m) == 1 and m > 1 (extended Eucldiean;
/// the result is reduced into [0, m)).
pub const modInverse = @import("sa_crypto_asym_keygen.zig").modInverse;

/// Miller-Rabin probable-prime test: trial division by the
/// primes < 256, then 12 random bases. n must be odd and > 2.
/// Randomness comes from the OS CSPRNG through the runtime's io
/// layer (the same source as sa_crypto_random_bytes).
pub const isProbablePrime = @import("sa_crypto_asym_keygen.zig").isProbablePrime;

/// A random prime of exactly half_bits bits (top two bits set,
/// which also biases the p*q product toward the full length;
/// the caller still checks the product's bit length exactly).
pub const genPrime = @import("sa_crypto_asym_keygen.zig").genPrime;

pub const GeneratedKeypair = @import("sa_crypto_asym_keygen.zig").GeneratedKeypair;

pub const derInt = @import("sa_crypto_asym_keygen.zig").derInt;

pub const derSeq = @import("sa_crypto_asym_keygen.zig").derSeq;

pub const rsaAlgIdSeq = @import("sa_crypto_asym_keygen.zig").rsaAlgIdSeq;

pub const generateRsaKeypair = @import("sa_crypto_asym_keygen.zig").generateRsaKeypair;

pub const sa_rsa_generate_keypair = @import("sa_crypto_asym_keygen.zig").sa_rsa_generate_keypair;

pub export fn sa_rsa_spki_to_jwk(der_ptr: ?[*]const u8, der_len: u64, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const der = inSlice(der_ptr, der_len) orelse return ERR_INVALID;
    const pub_key = parseRsaPublic(der) catch return ERR_INVALID;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const enc = std.base64.url_safe_no_pad.Encoder;
    const n_b64 = a.alloc(u8, enc.calcSize(pub_key.n.len)) catch return ERR_NOMEM;
    const e_b64 = a.alloc(u8, enc.calcSize(pub_key.e.len)) catch return ERR_NOMEM;
    _ = enc.encode(n_b64, pub_key.n);
    _ = enc.encode(e_b64, pub_key.e);
    const json = std.fmt.allocPrint(a, "{{\"kty\":\"RSA\",\"n\":\"{s}\",\"e\":\"{s}\"}}", .{ n_b64, e_b64 }) catch return ERR_NOMEM;
    return writeOut(out_ptr, cap, out_len, json);
}

// ---------------- DER key import for Ed25519 / ECDSA ----------------

/// Shared SPKI walk: returns (algorithm OID element, key bytes).
fn parseSpki(der: []const u8) error{Invalid}!struct { oid: Elem, key: []const u8 } {
    const outer = try topElem(der, 0x30);
    var s = try seqOf(outer);
    const alg = try s.next();
    const oid = try algOid(alg);
    const bits = try s.next();
    return .{ .oid = oid, .key = try bitStringBytes(bits) };
}

pub export fn sa_ed25519_public_key_from_spki(der_ptr: ?[*]const u8, der_len: u64, out_ptr: ?[*]u8) i32 {
    const der = inSlice(der_ptr, der_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const spki = parseSpki(der) catch return ERR_INVALID;
    if (!oidIs(spki.oid, &oid_ed25519)) return ERR_INVALID;
    if (spki.key.len != 32) return ERR_INVALID;
    out[0..32].* = spki.key[0..32].*;
    return OK;
}

pub export fn sa_ed25519_seed_from_pkcs8(der_ptr: ?[*]const u8, der_len: u64, out_ptr: ?[*]u8) i32 {
    const der = inSlice(der_ptr, der_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const outer = topElem(der, 0x30) catch return ERR_INVALID;
    var s = seqOf(outer) catch return ERR_INVALID;
    _ = s.next() catch return ERR_INVALID; // version
    const alg = s.next() catch return ERR_INVALID;
    const oid = algOid(alg) catch return ERR_INVALID;
    if (!oidIs(oid, &oid_ed25519)) return ERR_INVALID;
    const oct = s.next() catch return ERR_INVALID;
    if (oct.tag != 0x04) return ERR_INVALID;
    // CurvePrivateKey ::= OCTET STRING wrapping the 32-byte seed.
    var inner_pos: usize = 0;
    const inner = readElem(oct.content, &inner_pos) catch return ERR_INVALID;
    if (inner.tag != 0x04 or inner.content.len != 32 or inner_pos != oct.content.len) return ERR_INVALID;
    out[0..32].* = inner.content[0..32].*;
    return OK;
}

pub export fn sa_ecdsa_p256_public_key_from_spki(der_ptr: ?[*]const u8, der_len: u64, out_ptr: ?[*]u8) i32 {
    const der = inSlice(der_ptr, der_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const outer = topElem(der, 0x30) catch return ERR_INVALID;
    var s = seqOf(outer) catch return ERR_INVALID;
    const alg = s.next() catch return ERR_INVALID;
    var as = seqOf(alg) catch return ERR_INVALID;
    const oid1 = as.next() catch return ERR_INVALID;
    const oid2 = as.next() catch return ERR_INVALID;
    if (!oidIs(oid1, &oid_ec_public_key) or !oidIs(oid2, &oid_p256)) return ERR_INVALID;
    const bits = s.next() catch return ERR_INVALID;
    const point = bitStringBytes(bits) catch return ERR_INVALID;
    const pk = std.crypto.sign.ecdsa.EcdsaP256Sha256.PublicKey.fromSec1(point) catch return ERR_INVALID;
    const sec1 = pk.toUncompressedSec1();
    out[0..64].* = sec1[1..65].*;
    return OK;
}

// ---- ECDSA signature DER <-> raw r||s ----

pub export fn sa_ecdsa_signature_der_to_raw(der_ptr: ?[*]const u8, der_len: u64, out_ptr: ?[*]u8) i32 {
    const der = inSlice(der_ptr, der_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const sig = std.crypto.sign.ecdsa.EcdsaP256Sha256.Signature.fromDer(der) catch return ERR_INVALID;
    out[0..64].* = sig.toBytes();
    return OK;
}

pub export fn sa_ecdsa_signature_raw_to_der(raw_ptr: ?[*]const u8, out_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const raw = raw_ptr orelse return ERR_INVALID;
    // std's Signature.toDer panics on a zero integer component: its
    // DER encoder trims a zero r/s to an empty slice and then indexes
    // element 0 of it. A valid ECDSA r/s lies in [1, n-1], so a zero
    // component is invalid input for this face -- reject it with the
    // error code instead of crashing the host.
    if (std.mem.allEqual(u8, raw[0..32], 0) or std.mem.allEqual(u8, raw[32..64], 0)) return ERR_INVALID;
    const sig = std.crypto.sign.ecdsa.EcdsaP256Sha256.Signature.fromBytes(raw[0..64].*);
    var buf: [72]u8 = undefined;
    const der = sig.toDer(&buf);
    return writeOut(out_ptr, cap, out_len, der);
}

// ---------------- PEM ----------------

pub const sa_pem_decode = @import("sa_crypto_asym_x509.zig").sa_pem_decode;

// ---------------- x509 minimal reader ----------------

/// Walks a certificate to its TBSCertificate children and returns
/// the elements this face exposes. Uses my own DER walk for the
/// structural fields (SPKI / subject / validity raw elements).
pub const certParts = @import("sa_crypto_asym_x509.zig").certParts;

pub const sa_x509_spki = @import("sa_crypto_asym_x509.zig").sa_x509_spki;

pub const sa_x509_subject = @import("sa_crypto_asym_x509.zig").sa_x509_subject;

pub const sa_x509_subject_cn = @import("sa_crypto_asym_x509.zig").sa_x509_subject_cn;

pub const sa_x509_public_key = @import("sa_crypto_asym_x509.zig").sa_x509_public_key;

/// Days from civil (Howard Hinnant's algorithm), proleptic
/// Gregorian calendar.
pub const daysFromCivil = @import("sa_crypto_asym_x509.zig").daysFromCivil;

pub const parseUint = @import("sa_crypto_asym_x509.zig").parseUint;

/// Parses a DER Time element (UTCTime YYMMDDHHMMSSZ or
/// GeneralizedTime YYYYMMDDHHMMSSZ, Zulu only per RFC 5280) to
/// unix seconds.
pub const parseDerTime = @import("sa_crypto_asym_x509.zig").parseDerTime;

pub const sa_x509_validity = @import("sa_crypto_asym_x509.zig").sa_x509_validity;

// ---------------- tests (fixtures generated with openssl 3.0.13; see FINDINGS) ----------------

pub const unhex = @import("sa_crypto_asym_x509.zig").unhex;


