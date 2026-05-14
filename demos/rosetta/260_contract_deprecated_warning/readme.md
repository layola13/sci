# 260 - Contract Deprecated Warning

This tree keeps the legacy API contract split between the interface and the bridge.

- `iface/deprecated.saasm-iface` records the legacy entry point.
- `bridge/deprecated_bridge.saasm` publishes the implementation and deprecated note.
- `consumer/deprecated_consumer.saasm` keeps the usage site isolated from the bridge.
