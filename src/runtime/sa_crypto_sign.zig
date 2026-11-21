const std = @import("std");
const ERR_INVALID = @import("sa_crypto.zig").ERR_INVALID;
const OK = @import("sa_crypto.zig").OK;
pub const inSlice = @import("sa_crypto.zig").inSlice;

pub const Ed25519 = std.crypto.sign.Ed25519;

pub export fn sa_ed25519_public_key(seed_ptr: ?[*]const u8, out_ptr: ?[*]u8) i32 {
    const seed = seed_ptr orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const kp = Ed25519.KeyPair.generateDeterministic(seed[0..32].*) catch return ERR_INVALID;
    out[0..32].* = kp.public_key.toBytes();
    return OK;
}

pub export fn sa_ed25519_sign(seed_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const seed = seed_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const kp = Ed25519.KeyPair.generateDeterministic(seed[0..32].*) catch return ERR_INVALID;
    const sig = kp.sign(msg, null) catch return ERR_INVALID;
    out[0..64].* = sig.toBytes();
    return OK;
}

pub export fn sa_ed25519_verify(pk_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, sig_ptr: ?[*]const u8, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const pk_b = pk_ptr orelse return ERR_INVALID;
    const sig_b = sig_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const pk = Ed25519.PublicKey.fromBytes(pk_b[0..32].*) catch return ERR_INVALID;
    const sig = Ed25519.Signature.fromBytes(sig_b[0..64].*);
    Ed25519.Signature.verify(sig, msg, pk) catch {
        ov.* = 0;
        return OK;
    };
    ov.* = 1;
    return OK;
}

pub const EcdsaP256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

pub fn p256PublicKey(pk_xy: [*]const u8) ?EcdsaP256.PublicKey {
    var sec1: [65]u8 = undefined;
    sec1[0] = 0x04;
    @memcpy(sec1[1..65], pk_xy[0..64]);
    return EcdsaP256.PublicKey.fromSec1(&sec1) catch null;
}

pub export fn sa_ecdsa_p256_verify(pk_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, sig_ptr: ?[*]const u8, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const pk_b = pk_ptr orelse return ERR_INVALID;
    const sig_b = sig_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const pk = p256PublicKey(pk_b) orelse return ERR_INVALID;
    const sig = EcdsaP256.Signature.fromBytes(sig_b[0..64].*);
    EcdsaP256.Signature.verify(sig, msg, pk) catch {
        ov.* = 0;
        return OK;
    };
    ov.* = 1;
    return OK;
}

pub export fn sa_ecdsa_p256_verify_prehashed(pk_ptr: ?[*]const u8, digest_ptr: ?[*]const u8, sig_ptr: ?[*]const u8, out_valid: ?*u32) i32 {
    const ov = out_valid orelse return ERR_INVALID;
    ov.* = 0;
    const pk_b = pk_ptr orelse return ERR_INVALID;
    const dg_b = digest_ptr orelse return ERR_INVALID;
    const sig_b = sig_ptr orelse return ERR_INVALID;
    const pk = p256PublicKey(pk_b) orelse return ERR_INVALID;
    const sig = EcdsaP256.Signature.fromBytes(sig_b[0..64].*);
    EcdsaP256.Signature.verifyPrehashed(sig, dg_b[0..32].*, pk) catch {
        ov.* = 0;
        return OK;
    };
    ov.* = 1;
    return OK;
}

pub export fn sa_ecdsa_p256_sign(priv_ptr: ?[*]const u8, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8) i32 {
    const priv = priv_ptr orelse return ERR_INVALID;
    const msg = inSlice(msg_ptr, msg_len) orelse return ERR_INVALID;
    const out = out_ptr orelse return ERR_INVALID;
    const sk = EcdsaP256.SecretKey.fromBytes(priv[0..32].*) catch return ERR_INVALID;
    const kp = EcdsaP256.KeyPair.fromSecretKey(sk) catch return ERR_INVALID;
    const sig = kp.sign(msg, null) catch return ERR_INVALID;
    out[0..64].* = sig.toBytes();
    return OK;
}
