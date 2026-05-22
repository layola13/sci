# 252 - Contract Error Code Mapping

This tree splits the public error-code mapping contract from the exported bridge.

- `iface/error_codes.sai` declares the public mapper.
- `bridge/error_map.sa` owns the mapping logic and export.
- `consumer/error_consumer.sa` checks the returned error code.
