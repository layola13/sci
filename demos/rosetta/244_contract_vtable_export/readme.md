# 244 - Contract Vtable Export

This tree splits vtable export from the indirect call site.

- `bridge/button_vtable.sa` exports the `BUTTON_VT` vtable and the draw function.
- `consumer/vtable_consumer.sa` performs the `call_indirect` path.
- `main.sa` stays thin and only checks the consumer result.
