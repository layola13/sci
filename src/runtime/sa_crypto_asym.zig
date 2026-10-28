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

const std = @import("std");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_NOT_FOUND: i32 = 3;
const ERR_ACCESS: i32 = 4;
const ERR_NOMEM: i32 = 5;
const ERR_TRUNCATED: i32 = 9;

fn inSlice(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return &.{};
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

fn writeOut(out_ptr: ?[*]u8, cap: u64, out_len: ?*u64, data: []const u8) i32 {
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

const Elem = struct {
    tag: u8,
    content: []const u8,
    full: []const u8,
};

fn readElem(bytes: []const u8, pos: *usize) error{Invalid}!Elem {
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
fn topElem(bytes: []const u8, tag: u8) error{Invalid}!Elem {
    var pos: usize = 0;
    const e = try readElem(bytes, &pos);
    if (e.tag != tag or pos != bytes.len) return error.Invalid;
    return e;
}

/// A cursor over the children of a SEQUENCE's content.
const Seq = struct {
    content: []const u8,
    pos: usize = 0,

    fn next(self: *Seq) error{Invalid}!Elem {
        if (self.pos >= self.content.len) return error.Invalid;
        return readElem(self.content, &self.pos);
    }
    fn peekTag(self: *const Seq) error{Invalid}!u8 {
        if (self.pos >= self.content.len) return error.Invalid;
        return self.content[self.pos];
    }
    fn done(self: *const Seq) bool {
        return self.pos >= self.content.len;
    }
};

fn seqOf(e: Elem) error{Invalid}!Seq {
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

const oid_rsa_encryption = [_]u8{ 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01 };
const oid_ec_public_key = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 };
const oid_p256 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };
const oid_ed25519 = [_]u8{ 0x2b, 0x65, 0x70 };
const oid_cn = [_]u8{ 0x55, 0x04, 0x03 };

fn oidIs(e: Elem, oid: []const u8) bool {
    return e.tag == 0x06 and std.mem.eql(u8, e.content, oid);
}

/// Parses an AlgorithmIdentifier SEQUENCE and returns its OID
/// element; parameters (if any) are left unread.
fn algOid(alg_seq: Elem) error{Invalid}!Elem {
    var s = try seqOf(alg_seq);
    const oid = try s.next();
    if (oid.tag != 0x06) return error.Invalid;
    return oid;
}

/// BIT STRING content octets (the leading unused-bits byte must
/// be zero for key material).
fn bitStringBytes(e: Elem) error{Invalid}![]const u8 {
    if (e.tag != 0x03 or e.content.len == 0) return error.Invalid;
    if (e.content[0] != 0) return error.Invalid;
    return e.content[1..];
}

// ---------------- RSA ----------------

const RsaPub = struct { n: []const u8, e: []const u8 };
const RsaPriv = struct { n: []const u8, d: []const u8 };

/// Accepts SPKI (SubjectPublicKeyInfo) or a bare PKCS#1
/// RSAPublicKey, auto-detected by the first child's tag.
fn parseRsaPublic(der: []const u8) error{Invalid}!RsaPub {
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
fn parseRsaPrivate(der: []const u8) error{Invalid}!RsaPriv {
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

const Managed = std.math.big.int.Managed;

fn bigFromBytes(a: std.mem.Allocator, bytes: []const u8) !Managed {
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

fn bigByteLen(v: *const Managed) usize {
    return (v.bitCountAbs() + 7) / 8;
}

fn modOf(a: std.mem.Allocator, x: *const Managed, n: *const Managed) !Managed {
    var q = try Managed.init(a);
    defer q.deinit();
    var r = try Managed.init(a);
    errdefer r.deinit();
    try Managed.divFloor(&q, &r, x, n);
    return r;
}

fn mulMod(a: std.mem.Allocator, x: *const Managed, y: *const Managed, n: *const Managed) !Managed {
    var t = try Managed.init(a);
    defer t.deinit();
    try t.mul(x, y);
    return modOf(a, &t, n);
}

/// base^exp mod n, exp as big-endian bytes, left-to-right
/// square-and-multiply. All allocations come from the caller's
/// arena, so intermediate values are intentionally not freed.
fn modExp(a: std.mem.Allocator, base: *const Managed, exp_bytes: []const u8, n: *const Managed) !Managed {
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

fn appendTlv(list: *std.ArrayList(u8), a: std.mem.Allocator, tag: u8, content: []const u8) !void {
    try list.append(a, tag);
    var lb: [3]u8 = undefined;
    try list.appendSlice(a, derLenBytes(content.len, &lb));
    try list.appendSlice(a, content);
}

/// DER INTEGER content for an unsigned magnitude (sign pad added
/// when the top bit is set, leading zeros stripped).
fn derIntContent(a: std.mem.Allocator, mag: []const u8) ![]u8 {
    var b = mag;
    while (b.len > 1 and b[0] == 0) b = b[1..];
    const pad: usize = if (b.len > 0 and b[0] & 0x80 != 0) 1 else 0;
    const out = try a.alloc(u8, b.len + pad);
    if (pad == 1) out[0] = 0;
    @memcpy(out[pad..], b);
    return out;
}

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
    const sig = std.crypto.sign.ecdsa.EcdsaP256Sha256.Signature.fromBytes(raw[0..64].*);
    var buf: [72]u8 = undefined;
    const der = sig.toDer(&buf);
    return writeOut(out_ptr, cap, out_len, der);
}

// ---------------- PEM ----------------

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

// ---------------- x509 minimal reader ----------------

/// Walks a certificate to its TBSCertificate children and returns
/// the elements this face exposes. Uses my own DER walk for the
/// structural fields (SPKI / subject / validity raw elements).
fn certParts(der: []const u8) error{Invalid}!struct {
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
    const parsed = std.crypto.Certificate.parse(.{ .buffer = cert, .index = 0 }) catch return ERR_INVALID;
    oa.* = switch (parsed.pub_key_algo) {
        .rsaEncryption => 1,
        .X9_62_id_ecPublicKey => 2,
        .curveEd25519 => 3,
        .rsassa_pss => 4,
    };
    return writeOut(out_ptr, cap, out_len, parsed.pubKey());
}

/// Days from civil (Howard Hinnant's algorithm), proleptic
/// Gregorian calendar.
fn daysFromCivil(y0: i64, m: u64, d: u64) i64 {
    var y = y0;
    if (m <= 2) y -= 1;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else -@divFloor(-y + 399, 400);
    const yoe: u64 = @intCast(y - era * 400);
    const mp: u64 = if (m > 2) m - 3 else m + 9;
    const doy: u64 = (153 * mp + 2) / 5 + d - 1;
    const doe: u64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + @as(i64, @intCast(doe)) - 719468;
}

fn parseUint(b: []const u8) ?u64 {
    var v: u64 = 0;
    for (b) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    return v;
}

/// Parses a DER Time element (UTCTime YYMMDDHHMMSSZ or
/// GeneralizedTime YYYYMMDDHHMMSSZ, Zulu only per RFC 5280) to
/// unix seconds.
fn parseDerTime(e: Elem) error{Invalid}!i64 {
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

// ---------------- tests (fixtures generated with openssl 3.0.13; see FINDINGS) ----------------

fn unhex(comptime s: []const u8) [s.len / 2]u8 {
    // The embedded openssl fixtures run to ~800 bytes; the default
    // comptime branch quota (1000) is far below the decode loop cost.
    @setEvalBranchQuota(100_000);
    var out: [s.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, s) catch unreachable;
    return out;
}

test "der: ecdsa signature raw<->der conversions" {
    // r = 1, s = 2 -> DER 30 06 02 01 01 02 01 02
    var raw: [64]u8 = @splat(0);
    raw[31] = 1;
    raw[63] = 2;
    var buf: [72]u8 = undefined;
    var len: u64 = 0;
    try std.testing.expectEqual(OK, sa_ecdsa_signature_raw_to_der(&raw, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, &unhex("3006020101020102"), buf[0..@intCast(len)]);
    var back: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ecdsa_signature_der_to_raw(&buf, len, &back));
    try std.testing.expectEqualSlices(u8, &raw, &back);
    // high-bit r needs the 0x00 sign pad in DER
    raw[0] = 0x80;
    try std.testing.expectEqual(OK, sa_ecdsa_signature_raw_to_der(&raw, &buf, buf.len, &len));
    try std.testing.expectEqual(OK, sa_ecdsa_signature_der_to_raw(&buf, len, &back));
    try std.testing.expectEqualSlices(u8, &raw, &back);
}

test "jwk: tiny RSA key encodes to the hand-computed SPKI" {
    // n = 0xa1b2 (b64url "obI"), e = 65537 (b64url "AQAB").
    var buf: [256]u8 = undefined;
    var len: u64 = 0;
    try std.testing.expectEqual(OK, sa_rsa_jwk_to_spki("obI".ptr, 3, "AQAB".ptr, 4, &buf, buf.len, &len));
    const expect = unhex("301e300d06092a864886f70d0101010500030d00300a020300a1b20203010001");
    try std.testing.expectEqualSlices(u8, &expect, buf[0..@intCast(len)]);
    // and the produced SPKI parses back through the RSA path
    const pk = try parseRsaPublic(buf[0..@intCast(len)]);
    try std.testing.expectEqualSlices(u8, &unhex("a1b2"), pk.n);
    try std.testing.expectEqualSlices(u8, &unhex("010001"), pk.e);
}

test "pem: decode a labelled block, reject a missing label" {
    const pem =
        \\-----BEGIN DEMO-----
        \\aGVsbG8=
        \\-----END DEMO-----
        \\
    ;
    var buf: [64]u8 = undefined;
    var len: u64 = 0;
    try std.testing.expectEqual(OK, sa_pem_decode(pem.ptr, pem.len, "DEMO".ptr, 4, &buf, buf.len, &len));
    try std.testing.expectEqualSlices(u8, "hello", buf[0..@intCast(len)]);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_pem_decode(pem.ptr, pem.len, "OTHER".ptr, 5, &buf, buf.len, &len));
}

test "der time: UTCTime windowing and GeneralizedTime" {
    var pos: usize = 0;
    const e1 = try readElem(&unhex("170d3235303130313030303030305a"), &pos); // 250101000000Z
    try std.testing.expectEqual(@as(i64, 1735689600), try parseDerTime(e1)); // 2025-01-01T00:00:00Z
    pos = 0;
    const e2 = try readElem(&unhex("180f32303330303130313030303030305a"), &pos); // 20300101000000Z
    try std.testing.expectEqual(@as(i64, 1893456000), try parseDerTime(e2)); // 2030-01-01T00:00:00Z
}

// ----------------------------------------------------------------------
// OpenSSL-generated fixtures (openssl 3.0.13 on the build box;
// commands in std-crypto-local/gen_fixtures.sh, hex extracted
// programmatically by gen_fixture_tests.py -- never hand-copied).
// RSA key is 1024-bit purely to keep the embedded fixtures small;
// the implementation itself is size-agnostic up to 4096-bit moduli.
// ----------------------------------------------------------------------

const fx_rsa_spki = unhex("30819f300d06092a864886f70d010101050003818d0030818902818100bf696ddd3e292b483bd0b89843cf292dda843c" ++
    "3df05f3fd9616241d5e9b9c5e9b5f47cfb47ac6f0fa7527524a6e30deba89ef84639c20ae19d24d052be59397920d66f" ++
    "47b7edd3e82c384b74a984104052e124a958f8c13fa490cd444cfb917712da4c610747f222d3c482b0cfe47a398569ac" ++
    "ca17170d5c37af3587d6e3e1730203010001");
const fx_rsa_pkcs8 = unhex("30820275020100300d06092a864886f70d01010105000482025f3082025b02010002818100bf696ddd3e292b483bd0b8" ++
    "9843cf292dda843c3df05f3fd9616241d5e9b9c5e9b5f47cfb47ac6f0fa7527524a6e30deba89ef84639c20ae19d24d0" ++
    "52be59397920d66f47b7edd3e82c384b74a984104052e124a958f8c13fa490cd444cfb917712da4c610747f222d3c482" ++
    "b0cfe47a398569acca17170d5c37af3587d6e3e17302030100010281800ec81080e65cfd87ad7ed7d282620c170b69ec" ++
    "d107b003594128fa568f9f16068f539b173898bb56e51ffc05e1916530ceabc016843d54e3c963df66946685868fef1e" ++
    "7971062c9829846be99854220ef35fdd2eb5bbefded81d0569b1bcbb4ed82d231b8feda75a3ce557075b81ff48e06cce" ++
    "5793d90c90794f7400be8687a9024100ddf4410bb84d48368a393818f13255469c5b1901d4cc3875e98cc749ee7cfa3b" ++
    "040b5e248b6b0c7a533f7edba4b6b2ce98cbec24f89ec5b7a3799e0a7e37109d024100dcc5d561e9162b91c28ad07ca3" ++
    "23875379c86ec48e1b27605e002705e4f90cb5a275f0e1bc7f341132302404ca655459154d08b4ca44aa19f0055ed3aa" ++
    "26754f024059094cb698de57a3995b4ec7a2aa204f4d15b63867d6eca750632ae6db86c312bd9299d76b1e2c493deff0" ++
    "c1c7978aaf19d8640888bb98710c611326fe6eb479023f5c4653e99882abb3409cc48753a885e75dff684cbf189a5cac" ++
    "ed6362135204fde5e965c4f40436bef93b25d2dac57f7bbc6b76381a5298c63e8c001678079b024100a8775184bbaad5" ++
    "5a63c53f0d5e9563f34dcdfb9b5f03f5b1a1ad076bef1aa89656511913556f76a26ffaeacb5f317025ee8435aa27ffb5" ++
    "0daec328d5250834b6");
const fx_rsa_pkcs1pub = unhex("30818902818100bf696ddd3e292b483bd0b89843cf292dda843c3df05f3fd9616241d5e9b9c5e9b5f47cfb47ac6f0fa7" ++
    "527524a6e30deba89ef84639c20ae19d24d052be59397920d66f47b7edd3e82c384b74a984104052e124a958f8c13fa4" ++
    "90cd444cfb917712da4c610747f222d3c482b0cfe47a398569acca17170d5c37af3587d6e3e1730203010001");
const fx_rsa_pkcs1priv = unhex("3082025b02010002818100bf696ddd3e292b483bd0b89843cf292dda843c3df05f3fd9616241d5e9b9c5e9b5f47cfb47" ++
    "ac6f0fa7527524a6e30deba89ef84639c20ae19d24d052be59397920d66f47b7edd3e82c384b74a984104052e124a958" ++
    "f8c13fa490cd444cfb917712da4c610747f222d3c482b0cfe47a398569acca17170d5c37af3587d6e3e1730203010001" ++
    "0281800ec81080e65cfd87ad7ed7d282620c170b69ecd107b003594128fa568f9f16068f539b173898bb56e51ffc05e1" ++
    "916530ceabc016843d54e3c963df66946685868fef1e7971062c9829846be99854220ef35fdd2eb5bbefded81d0569b1" ++
    "bcbb4ed82d231b8feda75a3ce557075b81ff48e06cce5793d90c90794f7400be8687a9024100ddf4410bb84d48368a39" ++
    "3818f13255469c5b1901d4cc3875e98cc749ee7cfa3b040b5e248b6b0c7a533f7edba4b6b2ce98cbec24f89ec5b7a379" ++
    "9e0a7e37109d024100dcc5d561e9162b91c28ad07ca323875379c86ec48e1b27605e002705e4f90cb5a275f0e1bc7f34" ++
    "1132302404ca655459154d08b4ca44aa19f0055ed3aa26754f024059094cb698de57a3995b4ec7a2aa204f4d15b63867" ++
    "d6eca750632ae6db86c312bd9299d76b1e2c493deff0c1c7978aaf19d8640888bb98710c611326fe6eb479023f5c4653" ++
    "e99882abb3409cc48753a885e75dff684cbf189a5caced6362135204fde5e965c4f40436bef93b25d2dac57f7bbc6b76" ++
    "381a5298c63e8c001678079b024100a8775184bbaad55a63c53f0d5e9563f34dcdfb9b5f03f5b1a1ad076bef1aa89656" ++
    "511913556f76a26ffaeacb5f317025ee8435aa27ffb50daec328d5250834b6");
const fx_rsa_digest = unhex("a8b88e533d8f58e2b54d28eac1181f1fb63304fabd9dd9831769d4b87fe2b322");
const fx_rsa_sig = unhex("6c45cac9aeeb06afcb676618346751b71e1d5f61c6f79743288779ae5eb2a3dac15e53ef660d7d9c3caec682c8e03b8a" ++
    "1d3479a4104b9c5480cce84fe9fabcbd10574fa5d698bc9b8924d3c9430616571213056b67fcac522d9bf9768776aa65" ++
    "5cb6b308e59f571bc70b70ca7c3be278ec5c82cc070fe950e8e3541343e0377b");
const fx_oaep_ct = unhex("8f53efcb3c96b1c2a1ca23d84262de43d8d35ab6136314a3494c3b6b44bfa5c08f31f81453b03ad05b967136ded11a4e" ++
    "7ea270e2cfec2fec5951cdc0b9af42ad7b4671797b7f37b06fd036cf9fdf5edc9b4b5e1c5efc63d90f7756c606ac5354" ++
    "4103208c63a77a9a970279763b69946b513595f4544580596f476452c84912cb");
const fx_ec_spki = unhex("3059301306072a8648ce3d020106082a8648ce3d03010703420004bdfbaf7067a81e6274248c69606a1d9d1600f750e0" ++
    "1adb87f5416b06d000964d186a2d85a05cd3064f3553852bf632376793edf95da86b9d71005b4b779f4834");
const fx_ec_sig_der = unhex("3045022100d89a5137688fc12293614562b627cb3337a3a549bdd7fe2fe4e82ba6153d77db0220569a17acf530e1bb97" ++
    "96ca3a5e21d6ea3f60f04765aeb4ef0da846d090f7ef30");
const fx_ed_spki = unhex("302a300506032b6570032100e893cea28a8043061591421231f1691ef282a78d1638e9e3adcb3e1cd2f127b8");
const fx_ed_pkcs8 = unhex("302e020100300506032b65700422042075132bca70a5cb5d16e190aa1e8a4437268a275771e9ed8c6f13976de51ee757");
const fx_ed_sig = unhex("d615eaf2c975c9e3cdd2e9a62d432a2c4f8e917ed4ea5c5cb7911264d458cb238bb2a7f33ffb38fdc2e5cbc9b9f96d96" ++
    "b8b8de33871411012a05e8204f23fe03");
const fx_ec_pub_bits = unhex("04bdfbaf7067a81e6274248c69606a1d9d1600f750e01adb87f5416b06d000964d186a2d85a05cd3064f3553852bf632" ++
    "376793edf95da86b9d71005b4b779f4834");
const fx_ed_pk = unhex("e893cea28a8043061591421231f1691ef282a78d1638e9e3adcb3e1cd2f127b8");
const fx_ec_cert = unhex("308201873082012da00302010202146159dc1d16a0d5e0b02beac3ece410ff28ab9fbf300a06082a8648ce3d04030230" ++
    "193117301506035504030c0e65632d6b61742e6578616d706c65301e170d3236313032383133303831345a170d333631" ++
    "3032353133303831345a30193117301506035504030c0e65632d6b61742e6578616d706c653059301306072a8648ce3d" ++
    "020106082a8648ce3d03010703420004bdfbaf7067a81e6274248c69606a1d9d1600f750e01adb87f5416b06d000964d" ++
    "186a2d85a05cd3064f3553852bf632376793edf95da86b9d71005b4b779f4834a3533051301d0603551d0e0416041410" ++
    "e76a863f9f35d2f31100d8a0a20def19dbb47c301f0603551d2304183016801410e76a863f9f35d2f31100d8a0a20def" ++
    "19dbb47c300f0603551d130101ff040530030101ff300a06082a8648ce3d040302034800304502210097ca25c4937e95" ++
    "b8dc562101490529107469a9ddde7ce363ed09e6f7c79d6c8f022050fa709f23223e29c7a8a8adee5791d08f4f18b335" ++
    "d2adf9f847ee745adf927d");
const fx_rsa_cert = unhex("30820315308201fda003020102021410fd196c19062cd60368508dd5f2fc8218e3e59c300d06092a864886f70d01010b" ++
    "0500301a3118301606035504030c0f7273612d6b61742e6578616d706c65301e170d3236313032383133303831345a17" ++
    "0d3336313032353133303831345a301a3118301606035504030c0f7273612d6b61742e6578616d706c6530820122300d" ++
    "06092a864886f70d01010105000382010f003082010a02820101009c243b8b72b1103880033eab3e70c5343526a92cd3" ++
    "2661361be434856e4fb8cd8934cb8ba8ef33f24d4c9b329805855bcc516e3d1def8936e237cf9a8a9b18244163c21944" ++
    "f577a286692ecbdf03352a8af9009f7fdd897ebb21add5f7a0fe7e9477a7e78ca1ac149b99458061983d0cbf5098f622" ++
    "450756c56b511e4a52cb18a829cac987ed4793d7286c33ea750705cb999c4d14c41fc376a1acc9731f1d3c7f193d1720" ++
    "db27c3ae7ec39a9ceb13b3647268dca2656b3bdea1f4db519a38a72db01416a4e8a9ef55c1d00c944b73e9696b80b4b5" ++
    "527e5d1984fefcd0a122b2fe7cba68607052ab200806fed53cbc39bc5d87f0aefe598f4e9f10a8f989a2790203010001" ++
    "a3533051301d0603551d0e04160414b06c215fbbe3652d96ee9ee27d1b9ee5743de4e4301f0603551d23041830168014" ++
    "b06c215fbbe3652d96ee9ee27d1b9ee5743de4e4300f0603551d130101ff040530030101ff300d06092a864886f70d01" ++
    "010b05000382010100091736be6291c4160169162c9bf60370dfac425bf89af5a2e97302c7c8dc87b4886f2c319f25bd" ++
    "6ad9e35820a8d4b634e04d572fa1e11d5e48e8a7008b319b6f1162e166162d339136ecdbe787ce59c6afe45cf47a79f5" ++
    "c681f04a89442ef50bc932b3df5981902316de8b4cbf67f24f551962dde276211434459c4b9d63bf9516480cb30540c6" ++
    "35adf7c7ca3c541fb0cd403016e517159c0461b074a2511e69df3500b147d12511017d5d475a5d0bf89784bbb3ae99a8" ++
    "d36bbea538f5a7652991098ed0f22d6c24ba0b25328a11434531533b4f32ec14761ab3bb0feaa6b6e4c15ecddf505244" ++
    "705e0db45bab33959ad7125faf24b1ab9d4aeada53731f469d");
const fx_ed_cert = unhex("308201463081f9a00302010202144baef5afa9ae92499951a1877af35a21ba75da1c300506032b657030193117301506" ++
    "035504030c0e65642d6b61742e6578616d706c65301e170d3236313032383133303831345a170d333631303235313330" ++
    "3831345a30193117301506035504030c0e65642d6b61742e6578616d706c65302a300506032b6570032100e893cea28a" ++
    "8043061591421231f1691ef282a78d1638e9e3adcb3e1cd2f127b8a3533051301d0603551d0e04160414f6341accca2a" ++
    "16626cc3e8a8caa543ab78766f1c301f0603551d23041830168014f6341accca2a16626cc3e8a8caa543ab78766f1c30" ++
    "0f0603551d130101ff040530030101ff300506032b6570034100239ea66297970abbadda363bdd6a1597b855d20fefdd" ++
    "a20be6a5ab4f5660a1cadf8657bc014a76281474790e9e3f166a0ba4d74b289b57eba975a0fb6c3a7401");
const fx_jwk_n = "v2lt3T4pK0g70LiYQ88pLdqEPD3wXz_ZYWJB1em5xem19Hz7R6xvD6dSdSSm4w3rqJ74RjnCCuGdJNBSvlk5eSDWb0e37dPoLDhLdKmEEEBS4SSpWPjBP6SQzURM-5F3EtpMYQdH8iLTxIKwz-R6OYVprMoXFw1cN681h9bj4XM";

test "openssl fixtures: RSA PKCS#1 v1.5 verify and sign agree byte-for-byte" {
    var valid: u32 = 0;
    // verify under both public key forms
    try std.testing.expectEqual(OK, sa_rsa_pkcs1_verify(&fx_rsa_spki, fx_rsa_spki.len, 0, &fx_rsa_digest, fx_rsa_digest.len, &fx_rsa_sig, fx_rsa_sig.len, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    try std.testing.expectEqual(OK, sa_rsa_pkcs1_verify(&fx_rsa_pkcs1pub, fx_rsa_pkcs1pub.len, 0, &fx_rsa_digest, fx_rsa_digest.len, &fx_rsa_sig, fx_rsa_sig.len, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    // tampered signature and wrong digest are "invalid", not errors
    var bad_sig = fx_rsa_sig;
    bad_sig[10] ^= 0x40;
    try std.testing.expectEqual(OK, sa_rsa_pkcs1_verify(&fx_rsa_spki, fx_rsa_spki.len, 0, &fx_rsa_digest, fx_rsa_digest.len, &bad_sig, bad_sig.len, &valid));
    try std.testing.expectEqual(@as(u32, 0), valid);
    var bad_digest = fx_rsa_digest;
    bad_digest[0] ^= 0x01;
    try std.testing.expectEqual(OK, sa_rsa_pkcs1_verify(&fx_rsa_spki, fx_rsa_spki.len, 0, &bad_digest, bad_digest.len, &fx_rsa_sig, fx_rsa_sig.len, &valid));
    try std.testing.expectEqual(@as(u32, 0), valid);
    // PKCS#1 v1.5 signing is deterministic: output must equal
    // openssl's signature bytes exactly, under both private key forms.
    var out_sig: [256]u8 = undefined;
    var out_len: usize = 0;
    try std.testing.expectEqual(OK, sa_rsa_pkcs1_sign(&fx_rsa_pkcs8, fx_rsa_pkcs8.len, 0, &fx_rsa_digest, fx_rsa_digest.len, &out_sig, out_sig.len, &out_len));
    try std.testing.expectEqual(@as(usize, 128), out_len);
    try std.testing.expectEqualSlices(u8, &fx_rsa_sig, out_sig[0..out_len]);
    try std.testing.expectEqual(OK, sa_rsa_pkcs1_sign(&fx_rsa_pkcs1priv, fx_rsa_pkcs1priv.len, 0, &fx_rsa_digest, fx_rsa_digest.len, &out_sig, out_sig.len, &out_len));
    try std.testing.expectEqualSlices(u8, &fx_rsa_sig, out_sig[0..out_len]);
    // JWK (n, e) import reconstructs the identical SPKI
    var jwk_spki: [256]u8 = undefined;
    var jwk_len: usize = 0;
    try std.testing.expectEqual(OK, sa_rsa_jwk_to_spki(fx_jwk_n.ptr, fx_jwk_n.len, "AQAB", 4, &jwk_spki, jwk_spki.len, &jwk_len));
    try std.testing.expectEqualSlices(u8, &fx_rsa_spki, jwk_spki[0..jwk_len]);
}

test "openssl fixtures: RSA OAEP-SHA256 decrypt" {
    var pt: [64]u8 = undefined;
    var pt_len: usize = 0;
    try std.testing.expectEqual(OK, sa_rsa_oaep_sha256_decrypt(&fx_rsa_pkcs8, fx_rsa_pkcs8.len, null, 0, &fx_oaep_ct, fx_oaep_ct.len, &pt, pt.len, &pt_len));
    try std.testing.expectEqualStrings("hello oaep", pt[0..pt_len]);
    try std.testing.expectEqual(OK, sa_rsa_oaep_sha256_decrypt(&fx_rsa_pkcs1priv, fx_rsa_pkcs1priv.len, null, 0, &fx_oaep_ct, fx_oaep_ct.len, &pt, pt.len, &pt_len));
    try std.testing.expectEqualStrings("hello oaep", pt[0..pt_len]);
    // tampered ciphertext: the single opaque ERR_ACCESS, never an oracle
    var bad = fx_oaep_ct;
    bad[100] ^= 0x01;
    try std.testing.expectEqual(ERR_ACCESS, sa_rsa_oaep_sha256_decrypt(&fx_rsa_pkcs8, fx_rsa_pkcs8.len, null, 0, &bad, bad.len, &pt, pt.len, &pt_len));
    // undersized output buffer reports the required size first
    try std.testing.expectEqual(ERR_TRUNCATED, sa_rsa_oaep_sha256_decrypt(&fx_rsa_pkcs8, fx_rsa_pkcs8.len, null, 0, &fx_oaep_ct, fx_oaep_ct.len, &pt, 4, &pt_len));
    try std.testing.expectEqual(@as(usize, 10), pt_len);
}


test "openssl fixtures: ECDSA P-256 SPKI import and DER signature interop" {
    const expect_xy = unhex("bdfbaf7067a81e6274248c69606a1d9d1600f750e01adb87f5416b06d000964d" ++ "186a2d85a05cd3064f3553852bf632376793edf95da86b9d71005b4b779f4834");
    var xy: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ecdsa_p256_public_key_from_spki(&fx_ec_spki, fx_ec_spki.len, &xy));
    try std.testing.expectEqualSlices(u8, &expect_xy, &xy);
    // openssl's DER signature over SHA-256("sample") converts to the
    // exact raw pair, converts back byte-identically, and verifies
    // through the sa_crypto.zig face.
    const expect_raw = unhex("d89a5137688fc12293614562b627cb3337a3a549bdd7fe2fe4e82ba6153d77db" ++ "569a17acf530e1bb9796ca3a5e21d6ea3f60f04765aeb4ef0da846d090f7ef30");
    var raw: [64]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ecdsa_signature_der_to_raw(&fx_ec_sig_der, fx_ec_sig_der.len, &raw));
    try std.testing.expectEqualSlices(u8, &expect_raw, &raw);
    var der: [72]u8 = undefined;
    var der_len: usize = 0;
    try std.testing.expectEqual(OK, sa_ecdsa_signature_raw_to_der(&raw, &der, der.len, &der_len));
    try std.testing.expectEqualSlices(u8, &fx_ec_sig_der, der[0..der_len]);
    var valid: u32 = 0;
    try std.testing.expectEqual(OK, @import("sa_crypto.zig").sa_ecdsa_p256_verify(&xy, "sample", 6, &raw, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
}

test "openssl fixtures: Ed25519 PKCS8/SPKI import and signature verify" {
    var seed: [32]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ed25519_seed_from_pkcs8(&fx_ed_pkcs8, fx_ed_pkcs8.len, &seed));
    try std.testing.expectEqualSlices(u8, &unhex("75132bca70a5cb5d16e190aa1e8a4437268a275771e9ed8c6f13976de51ee757"), &seed);
    var pk: [32]u8 = undefined;
    try std.testing.expectEqual(OK, sa_ed25519_public_key_from_spki(&fx_ed_spki, fx_ed_spki.len, &pk));
    try std.testing.expectEqualSlices(u8, &unhex("e893cea28a8043061591421231f1691ef282a78d1638e9e3adcb3e1cd2f127b8"), &pk);
    var valid: u32 = 0;
    try std.testing.expectEqual(OK, @import("sa_crypto.zig").sa_ed25519_verify(&pk, "sa jwt ed", 9, &fx_ed_sig, &valid));
    try std.testing.expectEqual(@as(u32, 1), valid);
    try std.testing.expectEqual(OK, @import("sa_crypto.zig").sa_ed25519_verify(&pk, "sa jwt eD", 9, &fx_ed_sig, &valid));
    try std.testing.expectEqual(@as(u32, 0), valid);
}


test "openssl fixtures: x509 minimal surface on EC, RSA and Ed25519 certs" {
    var buf: [1200]u8 = undefined;
    var n: usize = 0;
    // SPKI extraction agrees with the standalone SPKI openssl emitted
    try std.testing.expectEqual(OK, sa_x509_spki(&fx_ec_cert, fx_ec_cert.len, &buf, buf.len, &n));
    try std.testing.expectEqualSlices(u8, &fx_ec_spki, buf[0..n]);
    var algo: u32 = 0;
    var pkbuf: [1200]u8 = undefined;
    var pklen: usize = 0;
    // sa_x509_public_key returns the subjectPublicKey BIT STRING
    // contents (not the full SPKI): EC -> 0x04||x||y, Ed25519 -> the
    // raw 32-byte key, RSA -> the PKCS#1 RSAPublicKey DER.
    try std.testing.expectEqual(OK, sa_x509_public_key(&fx_ec_cert, fx_ec_cert.len, &pkbuf, pkbuf.len, &pklen, &algo));
    try std.testing.expectEqual(@as(u32, 2), algo); // EC
    try std.testing.expectEqualSlices(u8, &fx_ec_pub_bits, pkbuf[0..pklen]);
    try std.testing.expectEqual(OK, sa_x509_public_key(&fx_rsa_cert, fx_rsa_cert.len, &pkbuf, pkbuf.len, &pklen, &algo));
    try std.testing.expectEqual(@as(u32, 1), algo); // RSA
    try std.testing.expect(pklen > 200 and pkbuf[0] == 0x30);
    try std.testing.expectEqual(OK, sa_x509_public_key(&fx_ed_cert, fx_ed_cert.len, &pkbuf, pkbuf.len, &pklen, &algo));
    try std.testing.expectEqual(@as(u32, 3), algo); // Ed25519
    try std.testing.expectEqualSlices(u8, &fx_ed_pk, pkbuf[0..pklen]);
    // subject / CN
    var subj: [256]u8 = undefined;
    var subj_len: usize = 0;
    try std.testing.expectEqual(OK, sa_x509_subject(&fx_ec_cert, fx_ec_cert.len, &subj, subj.len, &subj_len));
    try std.testing.expect(std.mem.indexOf(u8, subj[0..subj_len], "ec-kat.example") != null);
    var cn: [128]u8 = undefined;
    var cn_len: usize = 0;
    try std.testing.expectEqual(OK, sa_x509_subject_cn(&fx_ec_cert, fx_ec_cert.len, &cn, cn.len, &cn_len));
    try std.testing.expectEqualStrings("ec-kat.example", cn[0..cn_len]);
    try std.testing.expectEqual(OK, sa_x509_subject_cn(&fx_rsa_cert, fx_rsa_cert.len, &cn, cn.len, &cn_len));
    try std.testing.expectEqualStrings("rsa-kat.example", cn[0..cn_len]);
    try std.testing.expectEqual(OK, sa_x509_subject_cn(&fx_ed_cert, fx_ed_cert.len, &cn, cn.len, &cn_len));
    try std.testing.expectEqualStrings("ed-kat.example", cn[0..cn_len]);
    // validity: openssl x509 -text reported
    //   notBefore Oct 28 12:58:38 2026 GMT, notAfter Oct 25 12:58:38 2036 GMT
    var nb: i64 = 0;
    var na: i64 = 0;
    try std.testing.expectEqual(OK, sa_x509_validity(&fx_ec_cert, fx_ec_cert.len, &nb, &na));
    try std.testing.expectEqual(@as(i64, 1793192894), nb);
    try std.testing.expectEqual(@as(i64, 2108552894), na);
}

