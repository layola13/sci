# 250 - Contract Const Export

This tree keeps the exported const and the consumer contract split apart.

- `iface/consts.saasm-iface` records the public entry point.
- `impl/const_impl.saasm` publishes the const and the implementation function.
- `consumer/const_consumer.saasm` imports both and checks the stable output.
