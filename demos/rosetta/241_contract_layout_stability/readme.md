# 241 - Contract Layout Stability

This tree is split into a public layout contract, a bridge, and a consumer.

- `layout/point.sal` defines the shared offsets.
- `bridge/point_bridge.sa` reads the layout and performs the sum.
- `consumer/point_consumer.sa` allocates the struct and checks the bridge result.
