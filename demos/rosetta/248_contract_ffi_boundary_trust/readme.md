# 248 - Contract Ffi Boundary Trust

This tree splits the layout from the FFI airlock.

- `layout/slot.saasm-layout` defines the slot used by the consumer.
- `bridge/boundary.saasm` keeps the unsafe pointer handling inside `@ffi_wrapper`.
- `consumer/boundary_consumer.saasm` calls the wrapper and checks the returned value.
