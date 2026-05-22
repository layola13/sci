# 250 - Contract Const Export

This tree keeps the exported const and the consumer contract split apart.

- `iface/consts.sai` records the public entry point.
- `impl/const_impl.sa` publishes the const and the implementation function.
- `consumer/const_consumer.sa` imports both and checks the stable output.
