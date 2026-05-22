# 248 - Contract Ffi Boundary Trust

This tree splits the layout from the FFI airlock.

- `layout/slot.sal` defines the slot used by the consumer.
- `bridge/boundary.sa` keeps the unsafe pointer handling inside `@ffi_wrapper`.
- `consumer/boundary_consumer.sa` calls the wrapper and checks the returned value.
