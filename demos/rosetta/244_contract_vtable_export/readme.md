# 244 - Contract Vtable Export

This tree splits vtable export from the indirect call site.

- `bridge/button_vtable.saasm` exports the `BUTTON_VT` vtable and the draw function.
- `consumer/vtable_consumer.saasm` performs the `call_indirect` path.
- `main.saasm` stays thin and only checks the consumer result.
