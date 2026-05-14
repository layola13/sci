# 258 - Contract Thread Local Isolation

This tree splits the TLS layout from the bridge that mutates it.

- `layout/tls.saasm-layout` keeps the shared offsets in one place.
- `bridge/tls_bridge.saasm` writes through the layout contract.
- `consumer/tls_consumer.saasm` allocates its own slot and checks the result.
