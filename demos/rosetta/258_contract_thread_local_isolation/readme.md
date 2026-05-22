# 258 - Contract Thread Local Isolation

This tree splits the TLS layout from the bridge that mutates it.

- `layout/tls.sal` keeps the shared offsets in one place.
- `bridge/tls_bridge.sa` writes through the layout contract.
- `consumer/tls_consumer.sa` allocates its own slot and checks the result.
