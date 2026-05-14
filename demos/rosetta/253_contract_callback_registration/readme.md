# 253 - Contract Callback Registration

This tree splits the callback vtable from the consumer that registers and invokes it indirectly.

- `bridge/callback_vtable.saasm` owns the callback implementation and exported vtable.
- `consumer/callback_consumer.saasm` constructs the slot and drives `call_indirect`.
- `main.saasm` only checks the consumer result.
