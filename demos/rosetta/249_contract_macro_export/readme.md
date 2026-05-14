# 249 - Contract Macro Export

This tree keeps the macro definition and the exported helper in separate support files.

- `macros/store.saasm` defines the reusable store macro.
- `bridge/macro_bridge.saasm` exports the helper used by the consumer.
- `consumer/macro_consumer.saasm` expands the macro and checks the result.
