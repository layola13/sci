# 243 - Contract Sig Mismatch Link

This demo is intentionally broken at the local call site and is expected to fail with `CapabilityMismatch`.

- `layout/slot.sal` records the expected slot size.
- `bridge/link_target.sa` exports a by-value `i32` API.
- `consumer/broken_consumer.sa` passes a pointer instead of an `i32`, so the compiler should diagnose the mismatch.
