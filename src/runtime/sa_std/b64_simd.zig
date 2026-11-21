const std = @import("std");
const builtin = @import("../sa_std.zig").builtin;
const constBytes = @import("../sa_std.zig").constBytes;
extern fn sa_b64dec_avx2(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64;
extern fn sa_cpu_has_avx2() c_int;

fn b64SimdSextetVal(c: u8) ?u8 {
    if (c >= 'A' and c <= 'Z') return c - 'A';
    if (c >= 'a' and c <= 'z') return c - 'a' + 26;
    if (c >= '0' and c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return null;
}

pub export fn sa_b64dec_simd(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64 {
    // AVX2 swizzle kernel (src/runtime/sa_b64_swizzle.c, Apache-2.0
    // attribution in-file) when the CPU supports it; otherwise the
    // portable Mula path below. Non-x86_64 builds stub the C side out.
    if (comptime builtin.cpu.arch == .x86_64) {
        if (sa_cpu_has_avx2() != 0) return sa_b64dec_avx2(in_ptr, in_len, out_ptr);
    }
    const input = constBytes(in_ptr, in_len) catch return 0;
    const n = input.len;
    if (n == 0) return 0;
    const out_p = out_ptr orelse return 0;
    const out = out_p[0 .. n / 4 * 3];
    const V32 = @Vector(32, u8);
    const zA: V32 = @splat(@as(u8, 'A'));
    const zZ: V32 = @splat(@as(u8, 'Z'));
    const zza: V32 = @splat(@as(u8, 'a'));
    const zzz: V32 = @splat(@as(u8, 'z'));
    const z0: V32 = @splat(@as(u8, '0'));
    const z9: V32 = @splat(@as(u8, '9'));
    const plus: V32 = @splat(@as(u8, '+'));
    const slash: V32 = @splat(@as(u8, '/'));
    const one: V32 = @splat(@as(u8, 1));
    const zero: V32 = @splat(@as(u8, 0));
    const o0_idx: [8]i32 = .{ 0, 4, 8, 12, 16, 20, 24, 28 };
    const o1_idx: [8]i32 = .{ 1, 5, 9, 13, 17, 21, 25, 29 };
    const o2_idx: [8]i32 = .{ 2, 6, 10, 14, 18, 22, 26, 30 };
    const o3_idx: [8]i32 = .{ 3, 7, 11, 15, 19, 23, 27, 31 };
    // NOTE: single-source shuffles only — this toolchain miscompiles
    // negative-mask cross-vector shuffles at -OReleaseFast
    // ("Assigned value does not match type of forward declaration").
    const m01_idx: [16]i32 = .{ 0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15 };
    const fin_idx: [24]i32 = .{ 0, 1, 16, 2, 3, 17, 4, 5, 18, 6, 7, 19, 8, 9, 20, 10, 11, 21, 12, 13, 22, 14, 15, 23 };
    var i: usize = 0;
    var w: usize = 0;
    while (i + 32 <= n) {
        const chunk: V32 = input[i..][0..32].*;
        const inAZ = @select(u8, chunk >= zA, @select(u8, chunk <= zZ, one, zero), zero);
        const inaz = @select(u8, chunk >= zza, @select(u8, chunk <= zzz, one, zero), zero);
        const in09 = @select(u8, chunk >= z0, @select(u8, chunk <= z9, one, zero), zero);
        const isPlus = @select(u8, chunk == plus, one, zero);
        const isSlash = @select(u8, chunk == slash, one, zero);
        const valid = inAZ | inaz | in09 | isPlus | isSlash;
        if (@reduce(.Min, valid) == 0) break;
        const sext = inAZ * (chunk -% zA) + inaz * (chunk -% (zza -% @as(V32, @splat(@as(u8, 26))))) + in09 * (chunk +% @as(V32, @splat(@as(u8, 4)))) + isPlus * @as(V32, @splat(@as(u8, 62))) + isSlash * @as(V32, @splat(@as(u8, 63)));
        const U = sext << @as(V32, @splat(@as(u8, 2)));
        const W = sext >> @as(V32, @splat(@as(u8, 4)));
        const X = (sext & @as(V32, @splat(@as(u8, 15)))) << @as(V32, @splat(@as(u8, 4)));
        const Y = sext >> @as(V32, @splat(@as(u8, 2)));
        const Z = (sext & @as(V32, @splat(@as(u8, 3)))) << @as(V32, @splat(@as(u8, 6)));
        const o0 = @shuffle(u8, U, @as(V32, undefined), o0_idx) | @shuffle(u8, W, @as(V32, undefined), o1_idx);
        const o1 = @shuffle(u8, X, @as(V32, undefined), o1_idx) | @shuffle(u8, Y, @as(V32, undefined), o2_idx);
        const o2 = @shuffle(u8, Z, @as(V32, undefined), o2_idx) | @shuffle(u8, sext, @as(V32, undefined), o3_idx);
        const o0a: [8]u8 = o0;
        const o1a: [8]u8 = o1;
        const o2a: [8]u8 = o2;
        const m01v: @Vector(16, u8) = o0a ++ o1a;
        const m01 = @shuffle(u8, m01v, @as(@Vector(16, u8), undefined), m01_idx);
        const m01a: [16]u8 = m01;
        const finv: @Vector(24, u8) = m01a ++ o2a;
        const out24 = @shuffle(u8, finv, @as(@Vector(24, u8), undefined), fin_idx);
        out[w..][0..24].* = out24;
        i += 32;
        w += 24;
    }
    while (i + 4 <= n) {
        const a = b64SimdSextetVal(input[i]) orelse break;
        const b = b64SimdSextetVal(input[i + 1]) orelse break;
        const c = b64SimdSextetVal(input[i + 2]) orelse break;
        const d = b64SimdSextetVal(input[i + 3]) orelse break;
        out[w] = (a << 2) | (b >> 4);
        out[w + 1] = ((b & 15) << 4) | (c >> 2);
        out[w + 2] = ((c & 3) << 6) | d;
        i += 4;
        w += 3;
    }
    return @intCast(w);
}
