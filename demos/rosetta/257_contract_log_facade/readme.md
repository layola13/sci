# 257 - Contract Log Facade

This tree splits the log facade contract from the exported bridge.

- `iface/log.saasm-iface` records the logging entry point.
- `bridge/log_bridge.saasm` owns the exported logger.
- `consumer/log_consumer.saasm` calls the facade with a shared message constant.
