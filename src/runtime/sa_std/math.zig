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
