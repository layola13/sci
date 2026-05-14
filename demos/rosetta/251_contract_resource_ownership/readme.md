# 251 - Contract Resource Ownership

This tree splits the ownership contract between the public declaration and the bridge.

- `iface/ownership.saasm-iface` describes the handle handoff.
- `bridge/ownership_bridge.saasm` mutates the handle in one place.
- `consumer/ownership_consumer.saasm` owns the allocation and the final check.
