# 241 - Contract Layout Stability

This tree is split into a public layout contract, a bridge, and a consumer.

- `layout/point.saasm-layout` defines the shared offsets.
- `bridge/point_bridge.saasm` reads the layout and performs the sum.
- `consumer/point_consumer.saasm` allocates the struct and checks the bridge result.
