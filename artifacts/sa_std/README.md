# libsa_std.a

This directory contains the checked-in static archive for the Zig-backed `sa_std` runtime.

## Build

```bash
zig build sa-std-static -Doptimize=Debug
```

## Source of Truth

- `src/runtime/sa_std.zig`
- `src/runtime/sa_std.h`
- `sa_std/*.sa`
- `build.zig`

## Produced Files

- `zig-out/lib/libsa_std.a`
- `zig-out/lib/libsa_std.so`
- `zig-out/include/sa_std.h`

The repository copy of the static archive is `artifacts/sa_std/libsa_std.a`.
