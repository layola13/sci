# 260 - Contract Deprecated Warning

This tree keeps the legacy API contract split between the interface and the bridge.

- `iface/deprecated.sai` records the legacy entry point.
- `bridge/deprecated_bridge.sa` publishes the implementation and deprecated note.
- `consumer/deprecated_consumer.sa` keeps the usage site isolated from the bridge.
