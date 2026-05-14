# 246 - Contract Semver Minor Update

This tree models a compatible API bump.

- `iface/minor.saasm-iface` keeps the public declarations stable.
- `impl/minor_impl.saasm` adds the extra helper while preserving the old entry point.
- `consumer/minor_consumer.saasm` only depends on the stable contract path.
