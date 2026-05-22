# 247 - Contract Semver Major Break

This tree keeps both v1 and v2 interfaces so the major break is explicit.

- `iface/v1.sai` preserves the old pointer-by-value contract.
- `iface/v2.sai` switches the public API to the newer handle shape.
- `bridge/major_break_impl.sa` and `consumer/major_consumer.sa` use the v2 path.
