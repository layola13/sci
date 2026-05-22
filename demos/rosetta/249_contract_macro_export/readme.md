# 249 - Contract Macro Export

This tree keeps the macro definition and the exported helper in separate support files.

- `macros/store.sa` defines the reusable store macro.
- `bridge/macro_bridge.sa` exports the helper used by the consumer.
- `consumer/macro_consumer.sa` expands the macro and checks the result.
