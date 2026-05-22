# 257 - Contract Log Facade

This tree splits the log facade contract from the exported bridge.

- `iface/log.sai` records the logging entry point.
- `bridge/log_bridge.sa` owns the exported logger.
- `consumer/log_consumer.sa` calls the facade with a shared message constant.
