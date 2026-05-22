# 251 - Contract Resource Ownership

This tree splits the ownership contract between the public declaration and the bridge.

- `iface/ownership.sai` describes the handle handoff.
- `bridge/ownership_bridge.sa` mutates the handle in one place.
- `consumer/ownership_consumer.sa` owns the allocation and the final check.
