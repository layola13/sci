# 245 - Contract Generic Monomorph Share

This tree keeps the public contract and the exported implementation separate.

- `iface/generic.sai` declares the shared entry point.
- `impl/generic_impl.sa` exports the implementation used by the consumer.
- `consumer/generic_consumer.sa` verifies the shared value and returns it to `main.sa`.
