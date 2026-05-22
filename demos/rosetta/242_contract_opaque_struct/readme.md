# 242 - Contract Opaque Struct

This tree keeps the public opaque view separate from the private bridge layout.

- `layout/public.sal` exposes only the opaque size.
- `layout/private.sal` holds the real offsets used by the bridge.
- `consumer/opaque_consumer.sa` treats the object as opaque and only checks the bridged result.
