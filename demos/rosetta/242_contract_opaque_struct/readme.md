# 242 - Contract Opaque Struct

This tree keeps the public opaque view separate from the private bridge layout.

- `layout/public.saasm-layout` exposes only the opaque size.
- `layout/private.saasm-layout` holds the real offsets used by the bridge.
- `consumer/opaque_consumer.saasm` treats the object as opaque and only checks the bridged result.
