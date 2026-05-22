# 253 - Contract Callback Registration

This tree splits the callback vtable from the consumer that registers and invokes it indirectly.

- `bridge/callback_vtable.sa` owns the callback implementation and exported vtable.
- `consumer/callback_consumer.sa` constructs the slot and drives `call_indirect`.
- `main.sa` only checks the consumer result.
