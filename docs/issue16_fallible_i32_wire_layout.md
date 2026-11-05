# Issue 16: Fallible i32 native wire layout

> **状态（2026-11-05 文档审计）**：2026-07-16 已修复缺陷记录；修复点（emit_llvm_llvmc_shim.c:957）、回归（tests/cli_smoke.zig）与 bc2sa-smoke 门经核实现仍在。

## Status

Fixed on 2026-07-16.

## Symptom

Native SA execution could read an invalid payload from an extern returning
`i32!`. SLA and SA text correctly use the stable fallible wire layout:

- status: `i32` at byte offset `0`;
- payload: return value at byte offset `8`.

The invalid read could remain hidden when the out-of-bounds bytes happened to
be zero, then corrupt later boolean policy calculations or aggregate fields.

## Root Cause

The LLVM-C native emitter stored the native extern result directly in an
addressable `{ i32, T }` aggregate. For `T = i32`, the platform ABI places the
payload at byte offset `4`, while SA consumers load fallible payloads from the
fixed wire offset `8`.

The native extern signature must retain `{ i32, T }` so it remains compatible
with the Zig/C runtime ABI. Only the addressable SA view needs repacking.

## Fix

`fallible_value_ptr` now extracts the native status and payload and writes them
to an SA wire aggregate shaped as `{ i32, i32 padding, T }`. This preserves the
native call ABI while making the returned pointer obey the stable SA offsets.

## Regression

`tests/cli_smoke.zig` builds and executes an SA program that:

1. receives `u64!` from `sa_fs_metadata`;
2. receives `i32!` from `sa_fs_metadata_free`;
3. reads status at offset `0` and the `i32` payload at offset `8`;
4. allocates a 35-byte aggregate and verifies a boolean sentinel at offset
   `31`.

The focused `zig build bc2sa-smoke` gate includes this regression.
