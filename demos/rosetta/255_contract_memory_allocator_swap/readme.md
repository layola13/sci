# 255 - Contract Memory Allocator Swap

This tree splits the allocator contract between the public declaration and the bridge.

- `iface/allocator.saasm-iface` describes the swapped allocator entry point.
- `bridge/allocator_bridge.saasm` mutates the handle in one place.
- `consumer/allocator_consumer.saasm` owns the allocation and the final check.
