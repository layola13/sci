# `sa_std` ABI Gates

The v1 symbol contract is split into two reviewed layers:

- `sa_std_symbols_v1.txt` contains the 535 exports declared directly by both
  runtime backends. It is also checked from source so an unsupported backend
  cannot silently drop an entry point.
- `sa_std_symbols_posix_v1.txt` adds 77 definitions currently emitted only by
  the POSIX artifact: imported protocol/netx exports, raw pthread adapters, and
  16 compatibility symbols. Linux static and shared artifacts therefore each
  have 612 managed definitions.

The artifact checker tracks every `sa_*` definition except the internal
`sa_host_pthread_*` C shim. It also tracks exactly these compatibility names:
`fd_open`, `fd_read`, `fd_close`, `mmap`, `munmap`, `signal`,
`pthread_spawn`, `pthread_spawn_detached`, `pthread_join`, `pthread_drop`,
`dlopen`, `dlsym`, `dlclose`, `sqlite3_prepare`, `sqlite3_step`, and
`sqlite3_finalize`. Compiler runtime and sanitizer definitions are excluded.

Run the lightweight source, parser, and C/Zig layout contracts with:

```sh
zig build sa-std-abi
```

Run the binary gate with an LLVM or GNU `nm` implementation that understands
ELF and COFF:

```sh
zig build sa-std-artifact-abi -Dabi-nm=/usr/lib/llvm-14/bin/llvm-nm
```

This builds and checks a Linux x86_64 static archive, a Linux x86_64 shared
object, and the COFF import library generated with the Windows x86_64 DLL.
The common gate remains part of `zig build test`; it also compiles the public C
header smoke for all three targets. The binary gate is separate because it
requires an external symbol reader and three runtime builds.

## Updating The Contract

Do not regenerate a baseline as a mechanical response to a failure. First
classify each missing or additional symbol as an intentional v1 ABI change.
Keep common backend exports in `sa_std_symbols_v1.txt`; keep only reviewed
POSIX additions in `sa_std_symbols_posix_v1.txt`. Both files are sorted by the
checker before comparison, but keeping them alphabetized makes review easier.

## Current Limits

- The Windows artifact currently exposes only the 535 common symbols. The 77
  POSIX additions are recorded separately, so this gate preserves the current
  platform surfaces but does not claim full Windows/POSIX export parity.
- Mach-O artifacts are not yet inspected. The layout gate does cross-check the
  C header on x86_64 macOS and Windows in addition to the native Linux run.
- A symbol gate proves presence, not function signatures or runtime behavior.
  The layout test freezes all public 64-bit C struct sizes, alignments, and
  offsets against an independent Zig ABI mirror, plus selected header function
  declarations. Native platform contract tests remain required.
- Backend-private implementation structs are outside the C/Zig layout mirror;
  any exported function that uses a private type still needs a signature-level
  audit.
