# 255 - Contract Memory Allocator Swap

This tree splits the allocator contract between the public declaration and the bridge.

- `iface/allocator.sai` describes the swapped allocator entry point.
- `bridge/allocator_bridge.sa` mutates the handle in one place.
- `consumer/allocator_consumer.sa` owns the allocation and the final check.
