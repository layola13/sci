# 252 - Contract Error Code Mapping

This tree splits the public error-code mapping contract from the exported bridge.

- `iface/error_codes.saasm-iface` declares the public mapper.
- `bridge/error_map.saasm` owns the mapping logic and export.
- `consumer/error_consumer.saasm` checks the returned error code.
