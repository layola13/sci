const std = @import("std");
const cryptoRandomU64 = @import("../sa_std.zig").cryptoRandomU64;
const policyAllows = @import("../sa_std.zig").policyAllows;

pub export fn sa_math_floor(x: f64) f64 {
    return @floor(x);
}

pub export fn sa_math_ceil(x: f64) f64 {
    return @ceil(x);
}

pub export fn sa_math_sqrt(x: f64) f64 {
    return @sqrt(x);
}

pub export fn sa_math_sin(x: f64) f64 {
    return @sin(x);
}

pub export fn sa_math_cos(x: f64) f64 {
    return @cos(x);
}

pub export fn sa_math_pow(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

pub export fn sa_math_random() f64 {
    if (!policyAllows(.random)) return 0;
    const u = cryptoRandomU64();
    return @as(f64, @floatFromInt(u >> 11)) * (1.0 / 9007199254740992.0);
}

pub export fn sa_math_exp(x: f64) f64 {
    return @exp(x);
}

pub export fn sa_math_log(x: f64) f64 {
    return @log(x);
}

pub export fn sa_math_log10(x: f64) f64 {
    return @log10(x);
}

pub export fn sa_math_log2(x: f64) f64 {
    return @log2(x);
}

pub export fn sa_math_tan(x: f64) f64 {
    return @tan(x);
}

pub export fn sa_math_asin(x: f64) f64 {
    return std.math.asin(x);
}

pub export fn sa_math_acos(x: f64) f64 {
    return std.math.acos(x);
}

pub export fn sa_math_atan(x: f64) f64 {
    return std.math.atan(x);
}

pub export fn sa_math_atan2(y: f64, x: f64) f64 {
    return std.math.atan2(y, x);
}

pub export fn sa_math_hypot(x: f64, y: f64) f64 {
    return std.math.hypot(x, y);
}

pub export fn sa_math_sinh(x: f64) f64 {
    return std.math.sinh(x);
}

pub export fn sa_math_cosh(x: f64) f64 {
    return std.math.cosh(x);
}

pub export fn sa_math_tanh(x: f64) f64 {
    return std.math.tanh(x);
}

pub export fn sa_math_expm1(x: f64) f64 {
    return std.math.expm1(x);
}

pub export fn sa_math_log1p(x: f64) f64 {
    return std.math.log1p(x);
}

pub export fn sa_math_frexp(x: f64, exp_out: *i32) f64 {
    const parts = std.math.frexp(x);
    exp_out.* = parts.exponent;
    return parts.significand;
}
