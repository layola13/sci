# 246 - Contract Semver Minor Update

This tree models a compatible API bump.

- `iface/minor.sai` keeps the public declarations stable.
- `impl/minor_impl.sa` adds the extra helper while preserving the old entry point.
- `consumer/minor_consumer.sa` only depends on the stable contract path.
