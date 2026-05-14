# 245 - Contract Generic Monomorph Share

This tree keeps the public contract and the exported implementation separate.

- `iface/generic.saasm-iface` declares the shared entry point.
- `impl/generic_impl.saasm` exports the implementation used by the consumer.
- `consumer/generic_consumer.saasm` verifies the shared value and returns it to `main.saasm`.
